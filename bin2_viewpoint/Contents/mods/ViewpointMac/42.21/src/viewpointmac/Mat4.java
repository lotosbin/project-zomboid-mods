package viewpointmac;

/**
 * 极简 4x4 矩阵（列主序 float[16]，与 OpenGL / {@code glUniformMatrix4fv(..., false, ...)} 直接兼容）。
 *
 * <p>刻意不引入任何数学库：一是模组要保持零依赖，二是列主序/转置这两个坑自己写一遍最不容易错。
 */
public final class Mat4 {

    /** 单位矩阵。 */
    public static float[] identity() {
        float[] m = new float[16];
        m[0] = 1f;
        m[5] = 1f;
        m[10] = 1f;
        m[15] = 1f;
        return m;
    }

    /**
     * 透视投影。
     *
     * @param fovyRad 垂直视场角（弧度）
     * @param aspect  宽高比
     */
    public static float[] perspective(float fovyRad, float aspect, float near, float far) {
        float[] m = new float[16];
        float f = (float) (1.0 / Math.tan(fovyRad * 0.5));
        m[0] = f / aspect;
        m[5] = f;
        m[10] = (far + near) / (near - far);
        m[11] = -1f;
        m[14] = (2f * far * near) / (near - far);
        return m;
    }

    /** 视图矩阵：右手系 lookAt（世界 Z 轴向上）。 */
    public static float[] lookAt(float[] eye, float[] center, float[] up) {
        float[] f = normalize(sub(center, eye));
        float[] s = normalize(cross(f, up));
        float[] u = cross(s, f);

        float[] m = new float[16];
        m[0] = s[0];
        m[4] = s[1];
        m[8] = s[2];
        m[1] = u[0];
        m[5] = u[1];
        m[9] = u[2];
        m[2] = -f[0];
        m[6] = -f[1];
        m[10] = -f[2];
        m[12] = -dot(s, eye);
        m[13] = -dot(u, eye);
        m[14] = dot(f, eye);
        m[15] = 1f;
        return m;
    }

    /** 矩阵乘法 result = a * b。 */
    public static float[] multiply(float[] a, float[] b) {
        float[] r = new float[16];
        for (int col = 0; col < 4; col++) {
            for (int row = 0; row < 4; row++) {
                float sum = 0f;
                for (int k = 0; k < 4; k++) {
                    sum += a[k * 4 + row] * b[col * 4 + k];
                }
                r[col * 4 + row] = sum;
            }
        }
        return r;
    }

    /** 平移矩阵。 */
    public static float[] translate(float x, float y, float z) {
        float[] m = identity();
        m[12] = x;
        m[13] = y;
        m[14] = z;
        return m;
    }

    public static float[] sub(float[] a, float[] b) {
        return new float[] {a[0] - b[0], a[1] - b[1], a[2] - b[2]};
    }

    public static float[] cross(float[] a, float[] b) {
        return new float[] {
            a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0],
        };
    }

    public static float dot(float[] a, float[] b) {
        return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    }

    public static float[] normalize(float[] v) {
        float len = (float) Math.sqrt(dot(v, v));
        if (len < 1e-6f) {
            return new float[] {0f, 0f, 1f};
        }
        return new float[] {v[0] / len, v[1] / len, v[2] / len};
    }

    private Mat4() {
    }
}
