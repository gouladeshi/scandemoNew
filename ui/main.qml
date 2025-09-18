import QtQuick 2.12
import QtQuick.Controls 2.5
import QtQuick.Layouts 1.12

ApplicationWindow {
    visible: true
    width: 800
    height: 480
    title: "扫码演示"

    property string groupName: "A组"
    property string shiftName: "白班"
    property int planTarget: 500
    property int realtimeCount: 0
    property string lastBarcode: ""
    property bool lastSuccess: false
    property string lastMessage: ""

    function refreshSettings() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "http://127.0.0.1:8080/api/settings");
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    var data = JSON.parse(xhr.responseText);
                    groupName = data.group;
                    shiftName = data.shift;
                    planTarget = data.plan_target;
                    realtimeCount = data.realtime_count;
                }
            }
        }
        xhr.send();
    }

    Component.onCompleted: refreshSettings()

    Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: refreshSettings()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 24
            Label { text: "当前班组：" + groupName; font.pixelSize: 24 }
            Label { text: "班次：" + shiftName; font.pixelSize: 24 }
            Label { text: "本班次排产量：" + planTarget; font.pixelSize: 24 }
            Label { text: "实时产量：" + realtimeCount; font.pixelSize: 24 }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            TextField {
                id: barcodeInput
                Layout.fillWidth: true
                placeholderText: "请输入或扫描条码，回车提交"
                font.pixelSize: 22
                onAccepted: submitBarcode(text)
            }
            Button { text: "提交"; onClicked: submitBarcode(barcodeInput.text) }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 120
            radius: 8
            color: lastBarcode === "" ? "#f0f0f0" : (lastSuccess ? "#d2f8d2" : "#ffd6d6")
            border.color: "#cccccc"
            border.width: 1

            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8
                Label { text: "条码：" + lastBarcode; font.pixelSize: 24 }
                Label { text: "结果：" + (lastSuccess ? "扫码正确" : "扫码错误"); font.pixelSize: 24 }
                Label { text: lastMessage; color: "#555"; font.pixelSize: 18 }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Button {
                text: "切换班组"
                onClicked: switchGroup()
            }
            Button {
                text: "正确条码"
                onClicked: triggerMock(true)
            }
            Button {
                text: "错误条码"
                onClicked: triggerMock(false)
            }
        }
    }

    function submitBarcode(code) {
        if (!code || code.length === 0) return;
        var xhr = new XMLHttpRequest();
        xhr.open("POST", "http://127.0.0.1:8080/api/process_barcode");
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    var data = JSON.parse(xhr.responseText);
                    lastBarcode = data.barcode;
                    lastSuccess = data.success;
                    lastMessage = data.message + " @ " + data.timestamp;
                    realtimeCount = data.realtime_count;
                    barcodeInput.text = "";
                    barcodeInput.forceActiveFocus();
                } else {
                    lastBarcode = code;
                    lastSuccess = false;
                    lastMessage = "请求错误：" + xhr.status;
                }
            }
        }
        xhr.send(JSON.stringify({ barcode: code }));
    }

    function switchGroup() {
        var target = groupName === "A组" ? "B组" : "A组";
        var xhr = new XMLHttpRequest();
        xhr.open("POST", "http://127.0.0.1:8080/api/set_group");
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                var data = JSON.parse(xhr.responseText);
                groupName = data.group;
                shiftName = data.shift;
                planTarget = data.plan_target;
                realtimeCount = data.realtime_count;
            }
        }
        xhr.send(JSON.stringify({ group: target }));
    }

    function triggerMock(ok) {
        var xhr = new XMLHttpRequest();
        xhr.open("POST", "http://127.0.0.1:8080/api/mock_scan");
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    var data = JSON.parse(xhr.responseText);
                    lastBarcode = data.barcode;
                    lastSuccess = data.success;
                    lastMessage = data.message + " @ " + data.timestamp;
                    realtimeCount = data.realtime_count;
                } else {
                    lastBarcode = ok ? "模拟-正确" : "模拟-错误";
                    lastSuccess = ok;
                    lastMessage = "请求错误：" + xhr.status;
                }
            }
        }
        xhr.send(JSON.stringify({ success: ok }));
    }
}
