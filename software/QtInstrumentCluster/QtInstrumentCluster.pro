QT += quick serialport multimedia network positioning location

qtHaveModule(svg) {
    QT += svg
    message("QtSvg detected: SVG weather icons enabled")
} else {
    message("QtSvg not found: build continues, but SVG assets may not render on target")
}

qtHaveModule(location):qtHaveModule(positioning) {
    QT += location positioning
    message("QtLocation/QtPositioning detected: Mapbox map support enabled")
} else {
    error("QtLocation/QtPositioning are required for Mapbox-only navigation.")
}

linux: QT += dbus

# You can make your code fail to compile if it uses deprecated APIs.
# In order to do so, uncomment the following line.
#DEFINES += QT_DISABLE_DEPRECATED_BEFORE=0x060000    # disables all the APIs deprecated before Qt 6.0.0

SOURCES += \
        src/bluetoothcontroller.cpp \
        main.cpp \
        src/externalmediacontroller.cpp \
        src/mainmodel.cpp \
        src/osrmrouteprovider.cpp \
        src/serialreceiver.cpp \
        src/systemsettingscontroller.cpp \
        src/weatherprovider.cpp

RESOURCES += qml.qrc

TRANSLATIONS += \
    QtInstrumentCluster_en_GB.ts
CONFIG += lrelease
CONFIG += embed_translations

# Additional import path used to resolve QML modules in Qt Creator's code model
QML_IMPORT_PATH =

# Additional import path used to resolve QML modules just for Qt Quick Designer
QML_DESIGNER_IMPORT_PATH =

# Default rules for deployment.
qnx: target.path = /tmp/$${TARGET}/bin
else: unix:!android: target.path = /opt/$${TARGET}/bin
!isEmpty(target.path): INSTALLS += target

HEADERS += \
    src/bluetoothcontroller.h \
    src/externalmediacontroller.h \
    src/mainmodel.h \
    src/mathutils.h \
    src/osrmrouteprovider.h \
    src/serialreceiver.h \
    src/weatherprovider.h \
    src/systemsettingscontroller.h
