import QtQuick 2.12
import QtQuick.Controls 2.5
import QtQuick.Layouts 1.12

ApplicationWindow {
    visible: true
    width: 800
    height: 480
    title: "Scan Demo"

    property string groupName: "-"
    property string shiftName: "-"
    property int planTarget: 0
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
            Label { text: "Group: " + groupName; font.pixelSize: 24 }
            Label { text: "Shift: " + shiftName; font.pixelSize: 24 }
            Label { text: "Plan: " + planTarget; font.pixelSize: 24 }
            Label { text: "Real-time: " + realtimeCount; font.pixelSize: 24 }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            TextField {
                id: barcodeInput
                Layout.fillWidth: true
                placeholderText: "Scan or input barcode, press Enter"
                font.pixelSize: 22
                onAccepted: submitBarcode(text)
            }
            Button { text: "Submit"; onClicked: submitBarcode(barcodeInput.text) }
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
                Label { text: "Barcode: " + lastBarcode; font.pixelSize: 24 }
                Label { text: "Result: " + (lastSuccess ? "SUCCESS" : "FAIL"); font.pixelSize: 24 }
                Label { text: lastMessage; color: "#555"; font.pixelSize: 18 }
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
                    lastMessage = "Request error: " + xhr.status;
                }
            }
        }
        xhr.send(JSON.stringify({ barcode: code }));
    }
}
