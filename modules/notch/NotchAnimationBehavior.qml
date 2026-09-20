import QtQuick
import qs.config
import qs.modules.theme

// Comportamiento estándar para animaciones de elementos que aparecen en el notch
Item {
    id: root

    // Propiedad para controlar la visibilidad con animaciones
    property bool isVisible: false

    // Aplicar las animaciones estándar del notch
    scale: isVisible ? 1.0 : 0.8
    opacity: isVisible ? 1.0 : 0.0
    visible: opacity > 0

    Behavior on scale {
        enabled: Motion.enabled
        NumberAnimation {
            duration: Motion.normal
            easing.type: Easing.OutBack
            easing.overshoot: 1.2
        }
    }

    Behavior on opacity {
        enabled: Motion.enabled
        NumberAnimation {
            duration: Motion.normal
            easing.type: Easing.OutQuart
        }
    }
}
