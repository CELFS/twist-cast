package app.twist.cast

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.app.KeyguardManager
import android.content.ClipData
import android.content.ClipboardManager
import android.view.accessibility.AccessibilityNodeInfo
import android.graphics.Path
import android.graphics.PointF
import android.os.Build
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent

class RemoteTouchService : AccessibilityService() {
    companion object {
        var active: RemoteTouchService? = null
            private set
        val supported: Boolean get() = Build.VERSION.SDK_INT >= 26
    }

    private var stroke: GestureDescription.StrokeDescription? = null
    private var position = PointF()
    private var rotation = 0
    private var pending: PointF? = null
    private var finishing = false
    private var inFlight = false
    private var touching = false
    private var generation = 0

    override fun onServiceConnected() { active = this }
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() { cancelTouch() }
    override fun onDestroy() {
        if (active === this) active = null
        cancelTouch()
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    fun pasteText(text: String): String {
        if (!CaptureService.running || text.isEmpty() || text.length > 16384 ||
            getSystemService(KeyguardManager::class.java).isKeyguardLocked) return "unavailable"
        val root = rootInActiveWindow ?: return "noField"
        try {
            val field = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return "noField"
            try {
                if (!field.isFocused || !field.isEditable || !field.isEnabled) return "noField"
                val clipboard = getSystemService(ClipboardManager::class.java)
                clipboard.setPrimaryClip(ClipData.newPlainText("TwistCast", text))
                // Let the target editor apply its own selection, formatting and input rules.
                return if (field.performAction(AccessibilityNodeInfo.ACTION_PASTE)) "pasted" else "copied"
            } finally {
                field.recycle()
            }
        } finally {
            root.recycle()
        }
    }

    fun cancelTouch() {
        generation++
        val previous = stroke
        if (Build.VERSION.SDK_INT >= 26 && previous != null) {
            dispatchGesture(GestureDescription.Builder().addStroke(previous.continueStroke(
                Path().apply { moveTo(position.x, position.y) }, 0, 1, false
            )).build(), null, null)
        }
        resetTouch()
    }

    private fun resetTouch() {
        touching = false
        inFlight = false
        finishing = false
        pending = null
        stroke = null
    }

    @Suppress("DEPRECATION")
    fun pointer(action: String, x: Double, y: Double, dx: Double, dy: Double, landscape: Boolean) {
        if (Build.VERSION.SDK_INT < 26) return
        if (action == "cancel" || getSystemService(KeyguardManager::class.java).isKeyguardLocked) {
            cancelTouch()
            return
        }
        val navigation = when (action) {
            "back" -> GLOBAL_ACTION_BACK
            "home" -> GLOBAL_ACTION_HOME
            "recents" -> GLOBAL_ACTION_RECENTS
            else -> null
        }
        if (navigation != null) {
            cancelTouch()
            performGlobalAction(navigation)
            return
        }
        val display = getSystemService(WindowManager::class.java).defaultDisplay
        val size = android.graphics.Point()
        display.getRealSize(size)
        if (size.x <= 0 || size.y <= 0 || landscape != (size.x > size.y)) {
            cancelTouch()
            return
        }
        val point = PointF((x * (size.x - 1)).toFloat(), (y * (size.y - 1)).toFloat())
        when (action) {
            "down" -> {
                cancelTouch()
                touching = true
                rotation = display.rotation
                position = point
                pending = point
                dispatchNext()
            }
            "move", "up" -> {
                if (!touching || finishing) return
                if (rotation != display.rotation) { cancelTouch(); return }
                pending = point
                finishing = action == "up"
                dispatchNext()
            }
            "scroll" -> {
                if (touching || inFlight) return
                val path = Path().apply {
                    moveTo(point.x, point.y)
                    lineTo((point.x - dx * size.x).toFloat().coerceIn(0f, (size.x - 1).toFloat()),
                        (point.y - dy * size.y).toFloat().coerceIn(0f, (size.y - 1).toFloat()))
                }
                dispatch(GestureDescription.StrokeDescription(path, 0, 90), false)
            }
        }
    }

    @android.annotation.TargetApi(26)
    private fun dispatchNext() {
        if (inFlight) return
        val next = pending ?: return
        pending = null
        val path = Path().apply {
            moveTo(position.x, position.y)
            if (next != position) lineTo(next.x, next.y)
        }
        val continuing = !finishing
        val nextStroke = stroke?.continueStroke(path, 0, 30, continuing)
            ?: GestureDescription.StrokeDescription(path, 0, 1, continuing)
        position = next
        dispatch(nextStroke, continuing)
    }

    private fun dispatch(next: GestureDescription.StrokeDescription, continuing: Boolean) {
        val current = generation
        inFlight = true
        stroke = if (continuing) next else null
        val accepted = dispatchGesture(GestureDescription.Builder().addStroke(next).build(),
            object : GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    if (current != generation) return
                    inFlight = false
                    if (continuing) dispatchNext() else resetTouch()
                }
                override fun onCancelled(gestureDescription: GestureDescription?) {
                    if (current == generation) resetTouch()
                }
            }, null)
        if (!accepted) resetTouch()
    }
}
