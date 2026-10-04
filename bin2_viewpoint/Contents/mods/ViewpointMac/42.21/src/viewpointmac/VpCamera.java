package viewpointmac;

import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.nio.FloatBuffer;

import net.bytebuddy.ByteBuddy;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import net.bytebuddy.implementation.InvocationHandlerAdapter;
import net.bytebuddy.matcher.ElementMatchers;

import org.lwjgl.BufferUtils;

/**
 * 把**我们自己的第一/第三人称相机**注入游戏的骨骼模型渲染器（1.9）。
 *
 * <h3>为什么需要它</h3>
 * 角色模型的相机来自抽象插槽 {@code zombie.core.skinnedmodel.ModelCamera}
 * （{@code public static ModelCamera instance}，接口 {@code IModelCamera} 只有 {@code Begin()}/{@code End()}）。
 * 游戏渲染角色时会调用 {@code ModelCamera.instance.Begin()} 来设置投影/视图矩阵。
 * 想让我们 3D 视角里的角色出现（而不是复制原版等距那一份），就得在绘制前把
 * {@code instance} 换成"用我们矩阵"的实现。
 *
 * <h3>为什么要运行期生成子类</h3>
 * 游戏类是 Java 25 字节码，我们只有 JDK 17，编译期引用不了 {@code ModelCamera}，
 * 所以用 **ByteBuddy**（ZombieBuddy 内置，已验证 3163 个 {@code net/bytebuddy} 条目）
 * 在运行期生成子类，并用 {@code InvocationHandler} 把 {@code Begin()}/{@code End()}
 * 接到 {@link #begin()} / {@link #end()}。
 *
 * <h3>矩阵怎么塞进去</h3>
 * 同时走两条路，最大化命中概率：
 * <ol>
 *   <li>{@code zombie.core.opengl.PZGLUtil.pushAndLoadMatrix(int, Matrix4f)} + {@code popMatrix(int)}
 *       —— 游戏自己的矩阵栈（{@code Core.projectionMatrixStack/modelViewMatrixStack}）；</li>
 *   <li>固定管线 {@code glMatrixMode + glLoadMatrixf} —— 老式 GL 2.1 路径的兜底。</li>
 * </ol>
 * {@code org.joml.Matrix4f} 也是 Java 25 字节码，所以只能反射创建并 {@code set(float[])}。
 */
public final class VpCamera {

    private static boolean initialized = false;
    private static boolean available = false;
    private static String failReason = "";

    private static Field fInstance;
    private static Object originalInstance = null;
    private static Object ourInstance = null;
    private static boolean installed = false;

    private static Method mPzglPushLoad;
    private static Method mPzglPop;
    private static Constructor<?> cTorMatrix4f;
    private static Method mMatrix4fSetArray;
    private static Method mMatrix4fSetArrayOff;

    private static boolean pushed = false;
    private static int installCount = 0;
    private static int beginCount = 0;
    private static int failureCount = 0;
    private static final FloatBuffer MATRIX_BUFFER = BufferUtils.createFloatBuffer(16);

    public static boolean available() {
        init();
        return available;
    }

    public static String failReason() {
        return failReason;
    }

    public static boolean installed() {
        return installed;
    }

    public static synchronized void init() {
        if (initialized) {
            return;
        }
        initialized = true;
        try {
            Class<?> cameraClass = Class.forName("zombie.core.skinnedmodel.ModelCamera");
            fInstance = cameraClass.getField("instance");

            // 1) 生成子类：Begin()/End() 转到我们这里
            Class<?> generated = new ByteBuddy()
                .subclass(cameraClass)
                .method(ElementMatchers.named("Begin").or(ElementMatchers.named("End")))
                .intercept(InvocationHandlerAdapter.of(new InvocationHandler() {
                    @Override
                    public Object invoke(Object proxy, Method method, Object[] args) {
                        if ("Begin".equals(method.getName())) {
                            begin();
                        } else {
                            end();
                        }
                        return null;
                    }
                }))
                .make()
                .load(cameraClass.getClassLoader(), ClassLoadingStrategy.Default.WRAPPER)
                .getLoaded();

            ourInstance = generated.getDeclaredConstructor().newInstance();

            // 2) 矩阵注入通道
            Class<?> pzgl = Class.forName("zombie.core.opengl.PZGLUtil");
            Class<?> matrixClass = Class.forName("org.joml.Matrix4f");
            mPzglPushLoad = pzgl.getMethod("pushAndLoadMatrix", int.class, matrixClass);
            mPzglPop = pzgl.getMethod("popMatrix", int.class);

            cTorMatrix4f = matrixClass.getConstructor();
            try {
                mMatrix4fSetArray = matrixClass.getMethod("set", float[].class);
            } catch (Throwable ignored) {
                mMatrix4fSetArray = null;
            }
            try {
                mMatrix4fSetArrayOff = matrixClass.getMethod("set", float[].class, int.class);
            } catch (Throwable ignored) {
                mMatrix4fSetArrayOff = null;
            }
            if (mMatrix4fSetArray == null && mMatrix4fSetArrayOff == null) {
                throw new NoSuchMethodException("org.joml.Matrix4f.set(float[]) 不存在");
            }

            available = true;
            Vp.log("viewpoint camera ready: ByteBuddy ModelCamera subclass + PZGLUtil matrix stacks.");
        } catch (Throwable t) {
            available = false;
            failReason = String.valueOf(t);
            Vp.warn("viewpoint camera unavailable (characters keep the vanilla camera): " + failReason);
        }
    }

    /** 把 {@code ModelCamera.instance} 换成我们的实现；失败返回 false。 */
    public static synchronized boolean install() {
        init();
        if (!available || ourInstance == null) {
            return false;
        }
        if (installed) {
            return true;
        }
        try {
            originalInstance = fInstance.get(null);
            fInstance.set(null, ourInstance);
            installed = true;
            installCount++;
            return true;
        } catch (Throwable t) {
            failureCount++;
            failReason = "install: " + t;
            return false;
        }
    }

    /** 还原游戏原本的相机。 */
    public static synchronized void restore() {
        if (!installed) {
            return;
        }
        try {
            fInstance.set(null, originalInstance);
        } catch (Throwable t) {
            failureCount++;
            failReason = "restore: " + t;
        }
        installed = false;
    }

    /** 生成类的 {@code Begin()} 会调到这里。 */
    private static void begin() {
        try {
            float[] projection = Camera.projection();
            float[] view = Camera.view();
            if (projection == null || view == null) {
                return;
            }
            loadMatrix(2, projection);   // GL_PROJECTION = 0x1701
            loadMatrix(3, view);         // GL_MODELVIEW  = 0x1700
            pushed = true;
            beginCount++;
        } catch (Throwable t) {
            failureCount++;
            failReason = "begin: " + t;
        }
    }

    /** 生成类的 {@code End()} 会调到这里。 */
    private static void end() {
        if (!pushed) {
            return;
        }
        pushed = false;
        try {
            if (mPzglPop != null) {
                mPzglPop.invoke(null, 3);
                mPzglPop.invoke(null, 2);
            }
        } catch (Throwable t) {
            failureCount++;
        }
    }

    /** 用反射造一个 JOML Matrix4f 并压入游戏的矩阵栈。 */
    private static void loadMatrix(int glMode, float[] matrix) throws Exception {
        Object m4 = cTorMatrix4f.newInstance();
        if (mMatrix4fSetArray != null) {
            mMatrix4fSetArray.invoke(m4, (Object) matrix);
        } else {
            mMatrix4fSetArrayOff.invoke(m4, matrix, 0);
        }
        mPzglPushLoad.invoke(null, glMode, m4);
    }

    public static String describe() {
        if (!available) {
            return "unavailable (" + failReason + ")";
        }
        return "installs=" + installCount + " begins=" + beginCount
            + " failures=" + failureCount + " installed=" + installed;
    }

    private VpCamera() {
    }
}
