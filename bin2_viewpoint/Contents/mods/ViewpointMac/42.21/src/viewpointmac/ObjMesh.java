package viewpointmac;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/**
 * 极简 OBJ 解析器（P3.1）。
 *
 * <p>PZ Voxel Studio 的模型是标准 OBJ：`v x y z` / `vt u v` / `vn` / `f a/b/c`，
 * 文件头自带 {@code # PZ Voxel Studio — Z up, tile units}，坐标就是地块单位、Z 向上。
 *
 * <p>解析时直接把 {@code bind.} 里的变换（绕 Z 旋转 / 缩放 / 平移）**烘焙进顶点**，
 * 这样绘制时每个模型实例只需要一次平移，不用为每个实例准备矩阵。
 * 输出顶点格式与 {@link Scene3D} 一致：x, y, z, u, v, r, g, b, a（颜色固定为白，
 * 让原版贴图决定外观）。
 */
public final class ObjMesh {

    public static final int FLOATS_PER_VERTEX = 9;

    public final float[] vertices;
    public final int vertexCount;
    public final String texturePath;

    private ObjMesh(float[] vertices, int vertexCount, String texturePath) {
        this.vertices = vertices;
        this.vertexCount = vertexCount;
        this.texturePath = texturePath;
    }

    /** 解析并烘焙变换；失败返回 null。 */
    public static ObjMesh load(File objFile, VoxelPack.Bind bind) {
        if (objFile == null || !objFile.isFile()) {
            return null;
        }
        List<float[]> positions = new ArrayList<>();
        List<float[]> uvs = new ArrayList<>();
        List<int[]> triangles = new ArrayList<>();
        String materialLib = null;

        try (BufferedReader reader = new BufferedReader(
            new InputStreamReader(new FileInputStream(objFile), StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                line = line.trim();
                if (line.isEmpty() || line.charAt(0) == '#') {
                    continue;
                }
                if (line.startsWith("v ")) {
                    positions.add(parseTriple(line, 2));
                } else if (line.startsWith("vt ")) {
                    uvs.add(parseTriple(line, 3));
                } else if (line.startsWith("f ")) {
                    addFace(line, positions.size(), uvs.size(), triangles);
                } else if (line.startsWith("mtllib ")) {
                    materialLib = line.substring(7).trim();
                }
            }
        } catch (Throwable t) {
            Vp.warn("obj parse failed: " + objFile + " (" + t + ")");
            return null;
        }
        if (positions.isEmpty() || triangles.isEmpty()) {
            return null;
        }

        float rotation = (float) Math.toRadians(bind != null ? bind.rotationDeg : 0f);
        float cos = (float) Math.cos(rotation);
        float sin = (float) Math.sin(rotation);
        float scale = bind != null ? bind.scale : 1f;
        float ox = bind != null ? bind.offsetX : 0f;
        float oy = bind != null ? bind.offsetY : 0f;
        float oz = bind != null ? bind.offsetZ : 0f;

        int count = triangles.size() * 3;
        float[] out = new float[count * FLOATS_PER_VERTEX];
        int cursor = 0;
        for (int[] tri : triangles) {
            for (int corner = 0; corner < 3; corner++) {
                int positionIndex = tri[corner * 2];
                int uvIndex = tri[corner * 2 + 1];
                float[] p = positionIndex >= 0 && positionIndex < positions.size()
                    ? positions.get(positionIndex) : new float[] {0f, 0f, 0f};
                float u = 0.5f;
                float v = 0.5f;
                if (uvIndex >= 0 && uvIndex < uvs.size()) {
                    float[] uv = uvs.get(uvIndex);
                    u = uv[0];
                    v = uv[1];
                }
                float x = p[0] * scale;
                float y = p[1] * scale;
                float z = p[2] * scale;
                // 绕 Z 轴旋转（PZ 的等距朝向），再平移
                float rx = x * cos - y * sin + ox;
                float ry = x * sin + y * cos + oy;
                float rz = z + oz;

                out[cursor] = rx;
                out[cursor + 1] = ry;
                out[cursor + 2] = rz;
                out[cursor + 3] = u;
                out[cursor + 4] = v;
                out[cursor + 5] = 1f;
                out[cursor + 6] = 1f;
                out[cursor + 7] = 1f;
                out[cursor + 8] = 1f;
                cursor += FLOATS_PER_VERTEX;
            }
        }
        return new ObjMesh(out, count, resolveTexture(objFile, materialLib));
    }

    private static float[] parseTriple(String line, int limit) {
        String[] parts = line.split("\\s+");
        float[] result = new float[3];
        for (int i = 0; i < 3 && i + 1 < parts.length && i < limit; i++) {
            try {
                result[i] = Float.parseFloat(parts[i + 1]);
            } catch (Throwable ignored) {
                result[i] = 0f;
            }
        }
        return result;
    }

    /** 支持 `f a/b/c`、`f a//c`、`f a`，多边形按扇形三角化。 */
    private static void addFace(String line, int positionCount, int uvCount, List<int[]> out) {
        String[] parts = line.split("\\s+");
        if (parts.length < 4) {
            return;
        }
        int corners = parts.length - 1;
        int[] positionIndex = new int[corners];
        int[] uvIndex = new int[corners];
        for (int i = 0; i < corners; i++) {
            String token = parts[i + 1];
            String[] sub = token.split("/");
            positionIndex[i] = resolveIndex(sub.length > 0 ? sub[0] : "", positionCount);
            uvIndex[i] = sub.length > 1 ? resolveIndex(sub[1], uvCount) : -1;
        }
        for (int i = 1; i + 1 < corners; i++) {
            out.add(new int[] {
                positionIndex[0], uvIndex[0],
                positionIndex[i], uvIndex[i],
                positionIndex[i + 1], uvIndex[i + 1],
            });
        }
    }

    private static int resolveIndex(String token, int total) {
        if (token == null || token.isEmpty()) {
            return -1;
        }
        try {
            int value = Integer.parseInt(token);
            if (value > 0) {
                return value - 1;
            }
            if (value < 0) {
                return total + value;
            }
        } catch (Throwable ignored) {
            // 落到 -1
        }
        return -1;
    }

    /** 从 mtl 的 map_Kd 找贴图；找不到就退回同目录下的 *.png。 */
    private static String resolveTexture(File objFile, String materialLib) {
        File dir = objFile.getParentFile();
        String fromMtl = null;
        if (materialLib != null && dir != null) {
            File mtl = new File(dir, materialLib);
            if (mtl.isFile()) {
                try (BufferedReader reader = new BufferedReader(
                    new InputStreamReader(new FileInputStream(mtl), StandardCharsets.UTF_8))) {
                    String line;
                    while ((line = reader.readLine()) != null) {
                        String text = line.trim();
                        if (text.startsWith("map_Kd ")) {
                            fromMtl = text.substring(7).trim();
                            break;
                        }
                    }
                } catch (Throwable ignored) {
                    // 退回目录扫描
                }
            }
        }
        if (fromMtl != null && dir != null) {
            File texture = new File(dir, fromMtl);
            if (texture.isFile()) {
                return texture.getAbsolutePath();
            }
        }
        if (dir != null) {
            File[] pngs = dir.listFiles((d, name) -> name.toLowerCase().endsWith(".png"));
            if (pngs != null && pngs.length > 0) {
                // 优先 texture.png，其次其它
                for (File png : pngs) {
                    if ("texture.png".equalsIgnoreCase(png.getName())) {
                        return png.getAbsolutePath();
                    }
                }
                return pngs[0].getAbsolutePath();
            }
        }
        return null;
    }

}
