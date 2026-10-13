import android.os.SystemClock;
import android.view.InputDevice;
import android.view.InputEvent;
import android.view.MotionEvent;
import java.lang.reflect.Method;

/** Shell-only emulator probe: joystick + held attack, then skill with a third touch. */
public final class TouchProbe {
    private final Object manager;
    private final Method inject;
    private final float scale;
    private final float offsetX;
    private final float offsetY;
    private final long downTime = SystemClock.uptimeMillis();

    private TouchProbe(int width, int height) throws Exception {
        Class<?> type = Class.forName("android.hardware.input.InputManagerGlobal");
        manager = type.getMethod("getInstance").invoke(null);
        inject = type.getMethod("injectInputEvent", InputEvent.class, int.class);
        scale = Math.min(width / 1280f, height / 720f);
        offsetX = (width - 1280 * scale) / 2;
        offsetY = (height - 720 * scale) / 2;
    }

    private void send(int action, int count) throws Exception {
        float[][] positions = {{215, 610}, {1160, 630}, {980, 650}};
        MotionEvent.PointerProperties[] properties = new MotionEvent.PointerProperties[count];
        MotionEvent.PointerCoords[] coordinates = new MotionEvent.PointerCoords[count];
        for (int i = 0; i < count; i++) {
            properties[i] = new MotionEvent.PointerProperties();
            properties[i].id = i;
            properties[i].toolType = MotionEvent.TOOL_TYPE_FINGER;
            coordinates[i] = new MotionEvent.PointerCoords();
            coordinates[i].x = offsetX + positions[i][0] * scale;
            coordinates[i].y = offsetY + positions[i][1] * scale;
            coordinates[i].pressure = 1;
            coordinates[i].size = 1;
        }
        MotionEvent event = MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), action,
                count, properties, coordinates, 0, 0, 1, 1, 0, 0,
                InputDevice.SOURCE_TOUCHSCREEN, 0);
        try {
            if (!Boolean.TRUE.equals(inject.invoke(manager, event, 2))) {
                throw new IllegalStateException("Emulator rejected touch injection");
            }
        } finally {
            event.recycle();
        }
    }

    public static void main(String[] args) throws Exception {
        TouchProbe probe = new TouchProbe(Integer.parseInt(args[0]), Integer.parseInt(args[1]));
        probe.send(MotionEvent.ACTION_DOWN, 1);
        probe.send(MotionEvent.ACTION_POINTER_DOWN | (1 << MotionEvent.ACTION_POINTER_INDEX_SHIFT), 2);
        for (int step = 0; step < 50; step++) {
            probe.send(MotionEvent.ACTION_MOVE, 2);
            SystemClock.sleep(40);
        }
        probe.send(MotionEvent.ACTION_POINTER_DOWN | (2 << MotionEvent.ACTION_POINTER_INDEX_SHIFT), 3);
        SystemClock.sleep(80);
        probe.send(MotionEvent.ACTION_POINTER_UP | (2 << MotionEvent.ACTION_POINTER_INDEX_SHIFT), 3);
        for (int step = 0; step < 20; step++) {
            probe.send(MotionEvent.ACTION_MOVE, 2);
            SystemClock.sleep(40);
        }
        probe.send(MotionEvent.ACTION_POINTER_UP | (1 << MotionEvent.ACTION_POINTER_INDEX_SHIFT), 2);
        probe.send(MotionEvent.ACTION_UP, 1);
        System.out.println("Injected independent movement, held attack and skill touches");
    }
}
