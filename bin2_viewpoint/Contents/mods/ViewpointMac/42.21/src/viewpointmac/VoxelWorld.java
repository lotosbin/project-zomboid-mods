package viewpointmac;

/**
 * 把游戏世界映射成 3D 几何（P2 / 1.6）。
 *
 * <p>映射原则：**逐物件**处理，尽量用原世界自己的数据。
 *
 * <ol>
 *   <li><b>地面</b>：每个有地板的地块铺一块平板，贴原版地板精灵；
 *       UV 向内缩 25%（等距菱形精灵内接正方形的临界点），保证不透明、能盖住游戏地面。</li>
 *   <li><b>物件</b>：遍历 {@code getObjects()} + {@code getWall()}，逐个物件处理：
 *       <ul>
 *         <li>物件自带 {@code SpriteModel}（载具、部分道具）→ **不画**，交给原世界那套 3D 渲染；</li>
 *         <li>模型包有 bind → 用模型包的真 3D 几何；</li>
 *         <li>都没有 → 画兜底盒子，高度按物件类型（树 3.2 / 墙 2.7 / 门 2.1 / 窗 1.5 / 家具 0.9）。</li>
 *       </ul></li>
 * </ol>
 *
 * <p>采样是预算式的：一个 (2R+1)² 的窗口有好几千格，用反射逐格读太贵，
 * 所以每帧只采 {@code voxelBudget} 格；记录的是世界坐标，补采期间旧数据仍画在正确位置。
 *
 * <p>网格按材质**分桶**输出，每个桶一次 {@code glDrawArrays}，避免逐盒子切换纹理。
 */
public final class VoxelWorld {

    private static final int MAX_TILES = 4096;

    /** 顶点格式：x, y, z, u, v, r, g, b, a */
    private static final int FLOATS_PER_VERTEX = 9;

    /** 网格缓冲上限（逐物件之后盒子更多，≈5500 个盒子）。 */
    private static final int MAX_FLOATS = 3_000_000;

    /** 单次重建最多收集多少个盒子（超出就丢弃远的）。 */
    private static final int MAX_BOXES = 20000;

    /** 每格最多处理几个物件（地板 + 双向墙 + 家具 + 树 + 装饰，取 6 留余量）。 */
    private static final int OBJ_PER_TILE = 6;

    // ---------------------------------------------------------------- 采样数据

    private static final short[] TILE_XS = new short[MAX_TILES];
    private static final short[] TILE_YS = new short[MAX_TILES];
    private static final byte[] TILE_TYPE = new byte[MAX_TILES];
    private static final short[] TILE_FLOOR_SLOT = new short[MAX_TILES];
    private static final byte[] TILE_OBJ_COUNT = new byte[MAX_TILES];

    private static final String[] OBJ_SPRITE = new String[MAX_TILES * OBJ_PER_TILE];
    private static final short[] OBJ_SLOT = new short[MAX_TILES * OBJ_PER_TILE];
    private static final byte[] OBJ_KIND = new byte[MAX_TILES * OBJ_PER_TILE];
    /** bit0 = 原版自带 SpriteModel（交给游戏自己画，我们不碰）。 */
    private static final byte[] OBJ_FLAGS = new byte[MAX_TILES * OBJ_PER_TILE];
    private static final Object[] OBJ_SCRATCH = new Object[OBJ_PER_TILE];

    // ---------------------------------------------------------------- 模型

    private static final int MAX_MODELS = 4096;
    private static final short[] MODEL_X = new short[MAX_MODELS];
    private static final short[] MODEL_Y = new short[MAX_MODELS];
    private static final Object[] MODEL_BIND = new Object[MAX_MODELS];
    private static int modelCount = 0;

    // ---------------------------------------------------------------- 盒子

    private static final short[] BOX_X = new short[MAX_BOXES];
    private static final short[] BOX_Y = new short[MAX_BOXES];
    private static final short[] BOX_SLOT = new short[MAX_BOXES];
    private static final byte[] BOX_KIND = new byte[MAX_BOXES];
    private static final float[] BOX_FADE = new float[MAX_BOXES];
    private static int boxCount = 0;

    // ---------------------------------------------------------------- 网格

    private static final float[] MESH = new float[MAX_FLOATS];
    private static int meshFloats = 0;
    private static int meshBoxes = 0;
    private static boolean meshOverflow = false;

    private static final int[] BUCKET_SLOT = new int[TileTextures.MAX_SLOTS + 1];
    private static final int[] BUCKET_START = new int[TileTextures.MAX_SLOTS + 1];
    private static final int[] BUCKET_COUNT = new int[TileTextures.MAX_SLOTS + 1];
    private static int bucketCount = 0;

    // ---------------------------------------------------------------- 统计与状态

    private static int centerX = Integer.MIN_VALUE;
    private static int centerY = Integer.MIN_VALUE;
    private static int centerZ = Integer.MIN_VALUE;
    private static int buildCursor = 0;
    private static int visibleCount = 0;
    private static int dataVersion = 0;
    private static int meshVersion = -1;

    private static int floorBoxes = 0;
    private static int objectBoxes = 0;
    private static int texturedBoxes = 0;
    private static int skippedOwnModel = 0;
    private static int treeBoxes = 0;
    private static int furnitureBoxes = 0;
    private static int modelBackedBoxes = 0;

    /** 兜底盒子的基础透明度：留出透视感，能看见游戏画面（地面除外）。 */
    private static final float ALPHA = 0.85f;

    /** 地面平板最外圈的透明度（内部一律 1.0，确保盖住游戏地面）。 */
    private static final float FLOOR_ALPHA_EDGE = 0.75f;

    /** 地面 UV 向内缩的比例：等距菱形精灵内接正方形的临界点就是 25%。 */
    private static final float FLOOR_UV_INSET = 0.25f;

    /** 有模型包几何时，"拖底"盒子的透明度倍率（模型盖上来时不糊）。 */
    private static final float MODEL_BASE_ALPHA = 0.6f;

    // ---------------------------------------------------------------- 公开访问

    public static float[] mesh() {
        return MESH;
    }

    public static int meshFloats() {
        return meshFloats;
    }

    public static int meshBoxes() {
        return meshBoxes;
    }

    public static int sampledTiles() {
        return visibleCount;
    }

    public static boolean overflowing() {
        return meshOverflow;
    }

    public static int bucketCount() {
        return bucketCount;
    }

    public static int bucketSlot(int index) {
        return index >= 0 && index < bucketCount ? BUCKET_SLOT[index] : -1;
    }

    public static int bucketStart(int index) {
        return index >= 0 && index < bucketCount ? BUCKET_START[index] : 0;
    }

    public static int bucketVertices(int index) {
        return index >= 0 && index < bucketCount ? BUCKET_COUNT[index] : 0;
    }

    /** 线框模式下网格里是线段而不是三角形，Scene3D 据此选择 GL_LINES。 */
    public static boolean meshIsLines() {
        return VpConfig.voxelWireframe();
    }

    public static int modelCount() {
        return modelCount;
    }

    public static float modelX(int index) {
        return index >= 0 && index < modelCount ? MODEL_X[index] : 0f;
    }

    public static float modelY(int index) {
        return index >= 0 && index < modelCount ? MODEL_Y[index] : 0f;
    }

    public static float modelZ(int index) {
        return centerZ;
    }

    public static VoxelPack.Bind modelBind(int index) {
        return index >= 0 && index < modelCount ? (VoxelPack.Bind) MODEL_BIND[index] : null;
    }

    // ---------------------------------------------------------------- 每帧推进

    /** 强制下一帧重建网格（改配置/贴图模式后立刻生效）。 */
    public static void invalidate() {
        meshVersion = -1;
        dataVersion++;
    }

    /** 每帧在渲染线程上调用：按预算推进采样，必要时重算网格。 */
    public static void update(float playerX, float playerY, float playerZ) {
        if (!VpConfig.voxel() || !WorldTiles.available()) {
            if (visibleCount != 0 || centerX != Integer.MIN_VALUE) {
                visibleCount = 0;
                meshFloats = 0;
                meshBoxes = 0;
                bucketCount = 0;
                // 关键：把中心也重置，否则下次打开时 buildCursor 已在末尾、不会重新采样
                centerX = Integer.MIN_VALUE;
                centerY = Integer.MIN_VALUE;
                centerZ = Integer.MIN_VALUE;
                buildCursor = 0;
                dataVersion++;
            }
            return;
        }

        int radius = VpConfig.voxelRadius();
        int span = radius * 2 + 1;
        int total = Math.min(span * span, MAX_TILES);

        int sx = (int) Math.floor(playerX);
        int sy = (int) Math.floor(playerY);
        int sz = (int) Math.round(playerZ);
        if (sx != centerX || sy != centerY || sz != centerZ) {
            centerX = sx;
            centerY = sy;
            centerZ = sz;
            buildCursor = 0;
            visibleCount = 0;
            dataVersion++;
            // 只有开启一个新窗口时才清空贴图槽位表：
            // 分帧采样会多次进入下面的循环，每帧清空会让先前采样的格子指向错误贴图。
            if (VpConfig.voxelTextured()) {
                TileTextures.reset();
            }
        }

        if (buildCursor < total) {
            Object cell = WorldTiles.cell();
            if (cell == null) {
                return;
            }
            int end = Math.min(total, buildCursor + Math.max(64, VpConfig.voxelBudget()));
            for (; buildCursor < end; buildCursor++) {
                sampleTile(cell, buildCursor, span, radius);
            }
            visibleCount = buildCursor;
            dataVersion++;
        }

        if (dataVersion != meshVersion) {
            rebuildMesh();
            meshVersion = dataVersion;
        }
    }

    /** 采样一格：地块类型 + 地板贴图 + 逐物件（精灵名 / 贴图 / 高度分类 / 是否原版自带模型）。 */
    private static void sampleTile(Object cell, int index, int span, int radius) {
        int dx = index % span - radius;
        int dy = index / span - radius;
        int wx = centerX + dx;
        int wy = centerY + dy;
        TILE_XS[index] = (short) wx;
        TILE_YS[index] = (short) wy;

        byte type = WorldTiles.type(cell, wx, wy, centerZ);
        TILE_TYPE[index] = type;
        // 注意：type == EMPTY 只说明"没有墙、不实心、没有地板"，
        // 但地块上仍可能站着物件（树/道具），所以这里不能整格跳过，照样要收集物件。

        // 地面：优先用"地板对象"的精灵
        Object floorObject = WorldTiles.lastFloorObject();
        TILE_FLOOR_SLOT[index] = (short) TileTextures.slotFor(floorObject);

        // 逐物件
        int count = WorldTiles.collectObjects(cell, wx, wy, centerZ, OBJ_SCRATCH, OBJ_PER_TILE);
        TILE_OBJ_COUNT[index] = (byte) count;
        int base = index * OBJ_PER_TILE;
        for (int s = 0; s < OBJ_PER_TILE; s++) {
            if (s >= count) {
                OBJ_SPRITE[base + s] = null;
                OBJ_SLOT[base + s] = -1;
                OBJ_KIND[base + s] = WorldTiles.KIND_FURNITURE;
                OBJ_FLAGS[base + s] = 0;
                continue;
            }
            Object object = OBJ_SCRATCH[s];
            OBJ_SPRITE[base + s] = WorldTiles.spriteNameOf(object);
            OBJ_SLOT[base + s] = (short) TileTextures.slotFor(object);
            OBJ_KIND[base + s] = WorldTiles.heightClassOf(object);
            OBJ_FLAGS[base + s] = (byte) (WorldTiles.hasSpriteModel(object) ? 1 : 0);
        }
    }

    // ---------------------------------------------------------------- 网格重建

    /** 只在数据变化时执行；成本 O(已采样的地块数 × 物件数)。 */
    private static void rebuildMesh() {
        boxCount = 0;
        meshFloats = 0;
        meshBoxes = 0;
        bucketCount = 0;
        modelCount = 0;
        floorBoxes = 0;
        objectBoxes = 0;
        texturedBoxes = 0;
        skippedOwnModel = 0;
        treeBoxes = 0;
        furnitureBoxes = 0;
        modelBackedBoxes = 0;
        meshOverflow = false;

        int radius = Math.max(1, VpConfig.voxelRadius());
        boolean models = VpConfig.voxelModels();
        boolean floors = VpConfig.voxelFloor();

        for (int i = 0; i < visibleCount && boxCount < MAX_BOXES; i++) {
            byte type = TILE_TYPE[i];
            int spriteCount = TILE_OBJ_COUNT[i];
            // 没有地块类型也没有物件，才整格跳过
            if (type == WorldTiles.EMPTY && spriteCount == 0) {
                continue;
            }
            float x = TILE_XS[i];
            float y = TILE_YS[i];
            float ddx = x + 0.5f - centerX;
            float ddy = y + 0.5f - centerY;
            float dist = (float) Math.sqrt(ddx * ddx + ddy * ddy);
            if (dist < 1.0f) {
                continue;
            }
            float fade = 1f - dist / radius;
            fade = Math.max(0.10f, Math.min(1f, fade * fade));

            // 1) 地面平板：不透明、UV 内缩，用来盖住游戏自己的地面
            //    （type == EMPTY 说明这格没有地板对象，就不要铺）
            if (floors && type != WorldTiles.EMPTY) {
                int floorSlot = TILE_FLOOR_SLOT[i];
                addBox(x, y, WorldTiles.KIND_FLOOR, floorSlot, fade, true);
            }

            // 2) 逐物件
            int base = i * OBJ_PER_TILE;
            for (int s = 0; s < spriteCount && boxCount < MAX_BOXES; s++) {
                // 原版自带 3D 模型的物件（载具等）交给游戏自己画，我们不画盒子盖它
                if ((OBJ_FLAGS[base + s] & 1) != 0 && VpConfig.voxelSkipOwn3d()) {
                    skippedOwnModel++;
                    continue;
                }
                String sprite = OBJ_SPRITE[base + s];
                byte kind = OBJ_KIND[base + s];

                int slot = OBJ_SLOT[base + s];

                // 模型包几何：作为"增强"叠加在盒子之上
                if (models && sprite != null && !sprite.isEmpty()) {
                    VoxelPack.Bind bind = VoxelPack.bind(sprite);
                    if (bind != null && modelCount < MAX_MODELS) {
                        MODEL_X[modelCount] = TILE_XS[i];
                        MODEL_Y[modelCount] = TILE_YS[i];
                        MODEL_BIND[modelCount] = bind;
                        modelCount++;
                        // 盒子照画，但更淡：模型没加载好（LRU / 每帧加载预算）或加载失败时，
                        // 这一格仍然有东西，不会出现空洞 —— 盒子就是"拖底"
                        addBox(x, y, kind, slot, fade, false, MODEL_BASE_ALPHA);
                        modelBackedBoxes++;
                        continue;
                    }
                }

                // 纯兜底盒子
                addBox(x, y, kind, slot, fade, false);
                if (kind == WorldTiles.KIND_TREE) {
                    treeBoxes++;
                } else if (kind == WorldTiles.KIND_FURNITURE) {
                    furnitureBoxes++;
                }
            }
        }

        // 按材质分桶输出：先无贴图（-1），再按槽位升序
        emitBucket(-1);
        for (int slot = 0; slot < TileTextures.MAX_SLOTS; slot++) {
            emitBucket(slot);
        }
        meshBoxes = boxCount;
    }

    private static void addBox(float x, float y, byte kind, int slot, float fade, boolean floor) {
        addBox(x, y, kind, slot, fade, floor, 1f);
    }

    /**
     * @param alphaScale 透明度倍率：有模型包几何的物件用 0.6，让"拖底"盒子更淡，
     *                   模型盖上来时不会糊在一起
     */
    private static void addBox(float x, float y, byte kind, int slot, float fade, boolean floor,
                               float alphaScale) {
        if (boxCount >= MAX_BOXES) {
            meshOverflow = true;
            return;
        }
        BOX_X[boxCount] = (short) x;
        BOX_Y[boxCount] = (short) y;
        BOX_SLOT[boxCount] = (short) slot;
        BOX_KIND[boxCount] = kind;
        BOX_FADE[boxCount] = fade * alphaScale;
        boxCount++;
        if (floor) {
            floorBoxes++;
        } else {
            objectBoxes++;
        }
        if (slot >= 0) {
            texturedBoxes++;
        }
    }

    /** 把属于该槽位的盒子写进网格，并登记成一个桶。 */
    private static void emitBucket(int slot) {
        int startVertices = meshFloats / FLOATS_PER_VERTEX;
        int emitted = 0;
        for (int i = 0; i < boxCount; i++) {
            if (BOX_SLOT[i] != slot) {
                continue;
            }
            byte kind = BOX_KIND[i];
            boolean floor = kind == WorldTiles.KIND_FLOOR;
            float r;
            float g;
            float b;
            if (slot >= 0) {
                // 有贴图：顶点色用白色做亮度调制，颜色完全来自原版精灵
                r = 1f;
                g = 1f;
                b = 1f;
            } else {
                float[] colour = colourOf(kind);
                r = colour[0];
                g = colour[1];
                b = colour[2];
            }
            // 地面必须**实心**：半透明的薄板在掠射角下互相叠加，会出现大块菱形摩尔纹
            // （用户截图里那一片"菱形"就是这么来的），也盖不住游戏地面。
            // 只在最外圈稍微淡出，避免边缘像刀切。
            float alpha = floor
                ? (BOX_FADE[i] <= 0.35f ? FLOOR_ALPHA_EDGE : 1.0f)
                : ALPHA * BOX_FADE[i];
            if (!appendBox(BOX_X[i], BOX_Y[i], centerZ, heightOf(kind), r, g, b, alpha, slot, floor)) {
                meshOverflow = true;
                break;
            }
            emitted++;
        }
        if (emitted == 0) {
            return;
        }
        if (bucketCount < BUCKET_SLOT.length) {
            BUCKET_SLOT[bucketCount] = slot;
            BUCKET_START[bucketCount] = startVertices;
            BUCKET_COUNT[bucketCount] = meshFloats / FLOATS_PER_VERTEX - startVertices;
            bucketCount++;
        }
    }

    /** 高度分类 → 高度（1 格 = 1 单位）。 */
    private static float heightOf(byte kind) {
        switch (kind) {
            case WorldTiles.KIND_TREE: return 3.2f;
            case WorldTiles.KIND_TALL: return 2.7f;
            case WorldTiles.KIND_DOOR: return 2.1f;
            case WorldTiles.KIND_WINDOW: return 1.5f;
            case WorldTiles.KIND_LOW: return 1.0f;
            case WorldTiles.KIND_FLOOR: return 0.03f;
            default: return 0.9f;
        }
    }

    /** 无贴图时的回退配色。 */
    private static float[] colourOf(byte kind) {
        switch (kind) {
            case WorldTiles.KIND_TREE: return new float[] {0.22f, 0.42f, 0.18f};
            case WorldTiles.KIND_TALL: return new float[] {0.60f, 0.62f, 0.66f};
            case WorldTiles.KIND_DOOR: return new float[] {0.72f, 0.52f, 0.30f};
            case WorldTiles.KIND_WINDOW: return new float[] {0.60f, 0.88f, 0.95f};
            case WorldTiles.KIND_LOW: return new float[] {0.34f, 0.70f, 0.36f};
            case WorldTiles.KIND_FLOOR: return new float[] {0.42f, 0.50f, 0.34f};
            default: return new float[] {0.78f, 0.64f, 0.44f};
        }
    }

    /**
     * 一整个地块的盒子。
     *
     * <p>绕序从**外侧看逆时针**（CCW），因为 Scene3D 打开背面剔除：
     * 站在方块里面时内侧会被剔掉，不会把整个屏幕糊成一块颜色。
     * 贴图 UV 取该精灵在图集里的矩形四角；地面会向内缩 25%（等距菱形内接正方形），
     * 保证采样到的都是不透明区域，从而真正盖住游戏地面。
     */
    private static boolean appendBox(float x, float y, float z0, float height,
                                     float r, float g, float b, float a, int slot, boolean floor) {
        float x0 = x;
        float x1 = x + 1f;
        float y0 = y;
        float y1 = y + 1f;
        float z1 = z0 + height;

        if (VpConfig.voxelWireframe()) {
            return wireBox(x0, y0, z0, x1, y1, z1, r, g, b, a);
        }

        float u0 = TileTextures.u0(slot);
        float v0 = TileTextures.v0(slot);
        float u1 = TileTextures.u1(slot);
        float v1 = TileTextures.v1(slot);
        if (slot < 0) {
            u0 = 0.5f;
            v0 = 0.5f;
            u1 = 0.5f;
            v1 = 0.5f;
        }

        // 顶面四个角对应的 UV。地面精灵是**等距菱形**，直接铺满正方形会留下四个透明角
        // （看起来就是"菱形拼贴 + 漏出游戏地面"），所以这里做菱形→正方形的重映射。
        float tau = u0;
        float tav = v0;
        float tbu = u1;
        float tbv = v0;
        float tcu = u1;
        float tcv = v1;
        float tdu = u0;
        float tdv = v1;
        if (slot >= 0 && floor) {
            String mode = VpConfig.floorUvMode();
            if ("inset".equals(mode)) {
                float iu = (u1 - u0) * FLOOR_UV_INSET;
                float iv = (v1 - v0) * FLOOR_UV_INSET;
                tau = u0 + iu;
                tav = v0 + iv;
                tbu = u1 - iu;
                tbv = v0 + iv;
                tcu = u1 - iu;
                tcv = v1 - iv;
                tdu = u0 + iu;
                tdv = v1 - iv;
            } else if ("isoflip".equals(mode)) {
                // 与 iso 相同，但 V 方向翻转 —— 用来验证原版纹理的 V 轴到底朝哪边。
                tau = mix(u0, u1, 0.50f);
                tav = mix(v0, v1, 0.00f);
                tbu = mix(u0, u1, 1.00f);
                tbv = mix(v0, v1, 0.50f);
                tcu = mix(u0, u1, 0.50f);
                tcv = mix(v0, v1, 1.00f);
                tdu = mix(u0, u1, 0.00f);
                tdv = mix(v0, v1, 0.50f);
            } else if (!"plain".equals(mode)) {
                // iso（默认）：等距菱形 → 正方形。
                //
                // 等距投影下 世界(x,y) → 屏幕(x-y, (x+y)/2)，所以地块四角与菱形四顶点的对应是固定的：
                //   西北角(-.5,-.5) → 屏幕正上方 = 菱形**上**顶点
                //   东北角(+.5,-.5) → 屏幕正右方 = 菱形**右**顶点
                //   东南角(+.5,+.5) → 屏幕正下方 = 菱形**下**顶点
                //   西南角(-.5,+.5) → 屏幕正左方 = 菱形**左**顶点
                // 于是每个角取菱形边中点的 UV：上=(mid,top) 右=(right,mid) 下=(mid,bottom) 左=(left,mid)
                tau = mix(u0, u1, 0.50f);
                tav = mix(v0, v1, 1.00f);
                tbu = mix(u0, u1, 1.00f);
                tbv = mix(v0, v1, 0.50f);
                tcu = mix(u0, u1, 0.50f);
                tcv = mix(v0, v1, 0.00f);
                tdu = mix(u0, u1, 0.00f);
                tdv = mix(v0, v1, 0.50f);
            }
        }

        return quad(x0, y0, z1, tau, tav, x1, y0, z1, tbu, tbv, x1, y1, z1, tcu, tcv, x0, y1, z1, tdu, tdv,
                r, g, b, a, 1.00f)
            && quad(x1, y1, z0, u0, v0, x0, y1, z0, u1, v0, x0, y1, z1, u1, v1, x1, y1, z1, u0, v1,
                r, g, b, a, 0.72f)
            && quad(x0, y1, z0, u0, v0, x0, y0, z0, u1, v0, x0, y0, z1, u1, v1, x0, y1, z1, u0, v1,
                r, g, b, a, 0.62f)
            && quad(x1, y0, z0, u0, v0, x1, y1, z0, u1, v0, x1, y1, z1, u1, v1, x1, y0, z1, u0, v1,
                r, g, b, a, 0.62f)
            && quad(x0, y0, z0, u0, v0, x1, y0, z0, u1, v0, x1, y0, z1, u1, v1, x0, y0, z1, u0, v1,
                r, g, b, a, 0.78f);
    }

    private static float mix(float a, float b, float t) {
        return a + (b - a) * t;
    }

    /** 线框盒（12 条棱）——调试用，不会遮住游戏画面。 */
    private static boolean wireBox(float x0, float y0, float z0, float x1, float y1, float z1,
                                   float r, float g, float b, float a) {
        float[][] corners = {
            {x0, y0, z0}, {x1, y0, z0}, {x1, y1, z0}, {x0, y1, z0},
            {x0, y0, z1}, {x1, y0, z1}, {x1, y1, z1}, {x0, y1, z1},
        };
        int[][] edges = {
            {0, 1}, {1, 2}, {2, 3}, {3, 0},
            {4, 5}, {5, 6}, {6, 7}, {7, 4},
            {0, 4}, {1, 5}, {2, 6}, {3, 7},
        };
        for (int[] e : edges) {
            if (meshFloats + 2 * FLOATS_PER_VERTEX > MAX_FLOATS) {
                return false;
            }
            for (int i = 0; i < 2; i++) {
                float[] c = corners[e[i]];
                push(c[0], c[1], c[2], 0.5f, 0.5f, r, g, b, a, 1.0f);
            }
        }
        return true;
    }

    private static boolean quad(float ax, float ay, float az, float au, float av,
                                float bx, float by, float bz, float bu, float bv,
                                float cx, float cy, float cz, float cu, float cv,
                                float dx, float dy, float dz, float du, float dv,
                                float r, float g, float b, float a, float shade) {
        if (meshFloats + 6 * FLOATS_PER_VERTEX > MAX_FLOATS) {
            return false;
        }
        push(ax, ay, az, au, av, r, g, b, a, shade);
        push(bx, by, bz, bu, bv, r, g, b, a, shade);
        push(cx, cy, cz, cu, cv, r, g, b, a, shade);
        push(ax, ay, az, au, av, r, g, b, a, shade);
        push(cx, cy, cz, cu, cv, r, g, b, a, shade);
        push(dx, dy, dz, du, dv, r, g, b, a, shade);
        return true;
    }

    private static void push(float x, float y, float z, float u, float v,
                             float r, float g, float b, float a, float shade) {
        int i = meshFloats;
        MESH[i] = x;
        MESH[i + 1] = y;
        MESH[i + 2] = z;
        MESH[i + 3] = u;
        MESH[i + 4] = v;
        MESH[i + 5] = r * shade;
        MESH[i + 6] = g * shade;
        MESH[i + 7] = b * shade;
        MESH[i + 8] = a;
        meshFloats += FLOATS_PER_VERTEX;
    }

    public static String describe() {
        if (!VpConfig.voxel()) {
            return "voxel world off";
        }
        if (!WorldTiles.available()) {
            return "voxel world unavailable (" + WorldTiles.failReason() + ")";
        }
        int total = (VpConfig.voxelRadius() * 2 + 1);
        total = Math.min(total * total, MAX_TILES);
        return "sampled=" + visibleCount + "/" + total + " boxes=" + boxCount
            + " (floor=" + floorBoxes + " object=" + objectBoxes
            + " tree=" + treeBoxes + " furniture=" + furnitureBoxes + ")"
            + " models=" + modelCount + " baseBoxes=" + modelBackedBoxes
            + " own3d=" + skippedOwnModel
            + " floorUv=" + VpConfig.floorUvMode()
            + " buckets=" + bucketCount + " " + TileTextures.describe()
            + " center=(" + centerX + ", " + centerY + ", " + centerZ + ")"
            + (meshOverflow ? " [vertex budget reached]" : "");
    }

    private VoxelWorld() {
    }
}
