package zbworkshopfix.test;

/**
 * 假的"被补丁目标"：形状与 {@code SteamWorkshopItem.submitUpdate()} 一样，返回 false（模拟确认框没确认）。
 */
public class DummyTarget {

    /** 记录原方法是否被执行过。 */
    public boolean originalRan;

    public boolean submitUpdate() {
        originalRan = true;
        return false;
    }
}
