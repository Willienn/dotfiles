import qs.modules.common
import QtQuick

/**
 * Gráfico de linha simples (histórico dos últimos N pontos, 0 a maxValue).
 * O ponto mais novo fica sempre na borda direita.
 */
Canvas {
    id: canvas

    property var values: []
    property color lineColor: Appearance.m3colors.m3primary
    property real maxValue: 100
    property int maxPoints: 60

    onValuesChanged: requestPaint()
    onLineColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);

        const n = values.length;
        if (n < 2) return;

        const step = width / (maxPoints - 1);
        const pad = 2;
        const usable = height - pad * 2;

        function xAt(i) {
            return width - (n - 1 - i) * step;
        }
        function yAt(v) {
            const ratio = Math.max(0, Math.min(1, v / maxValue));
            return pad + usable - ratio * usable;
        }

        // Preenchimento
        ctx.beginPath();
        ctx.moveTo(xAt(0), height);
        for (let i = 0; i < n; i++) ctx.lineTo(xAt(i), yAt(values[i]));
        ctx.lineTo(xAt(n - 1), height);
        ctx.closePath();
        ctx.fillStyle = Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.18);
        ctx.fill();

        // Linha
        ctx.beginPath();
        ctx.moveTo(xAt(0), yAt(values[0]));
        for (let i = 1; i < n; i++) ctx.lineTo(xAt(i), yAt(values[i]));
        ctx.strokeStyle = lineColor.toString();
        ctx.lineWidth = 2;
        ctx.lineJoin = "round";
        ctx.stroke();
    }
}
