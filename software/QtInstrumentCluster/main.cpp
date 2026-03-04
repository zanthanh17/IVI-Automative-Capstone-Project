#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>

#include <QLocale>
#include <QTranslator>

#include "src/simulationcontroller.h"
#include "src/DriveTrain.h"
#include "src/mainmodel.h"
#include "src/serialreceiver.h"
#include "src/externalmediacontroller.h"

int main(int argc, char *argv[])
{
#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
    QCoreApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
#endif
    QGuiApplication app(argc, argv);

    QTranslator translator;
    const QStringList uiLanguages = QLocale::system().uiLanguages();
    for (const QString &locale : uiLanguages) {
        const QString baseName = "QtInstrumentCluster_" + QLocale(locale).name();
        if (translator.load(":/i18n/" + baseName)) {
            app.installTranslator(&translator);
            break;
        }
    }

    qmlRegisterType<SimulationController>("SimulationController", 1, 0, "SimulationController");
    qmlRegisterType<Drivetrain>("Drivetrain", 1, 0, "DriveTrain");

    qmlRegisterSingletonType<MainModel>("MainModelData", 1, 0, "MainModelData", [](QQmlEngine*, QJSEngine*) -> QObject* {
            return MainModel::instance();
        });

    qmlRegisterSingletonType(QUrl("qrc:///models/TellTalesModel.qml"), "TellTalesModel", 1, 0, "TellTalesModel");
    qmlRegisterSingletonType(QUrl("qrc:///models/MainModel.qml"), "MainModel", 1, 0, "MainModel");
    qmlRegisterSingletonType(QUrl("qrc:///models/Style.qml"), "Style", 1, 0, "Style");
    qmlRegisterSingletonType(QUrl("qrc:///models/Units.qml"), "Units", 1, 0, "Units");
    qmlRegisterSingletonType(QUrl("qrc:///models/NormalModeModel.qml"), "NormalModeModel", 1, 0, "NormalModeModel");
    qmlRegisterSingletonType(QUrl("qrc:///models/MediaPlayerModel.qml"), "MediaPlayerModel", 1, 0, "MediaPlayerModel");

    /* Register ExternalMediaController singleton cho QML */
    qmlRegisterSingletonType<ExternalMediaController>("ExternalMedia", 1, 0, "ExternalMedia",
        [](QQmlEngine*, QJSEngine*) -> QObject* {
            return ExternalMediaController::instance();
        });

    /*
     * Khởi tạo SerialReceiver và auto-connect tới STM32
     * - Trên PC host: tìm USB-TTL (CP2102/CH340) → COMx
     * - Trên Raspberry Pi: tìm /dev/ttyAMA0
     * Code GIỐNG HỆT, chỉ khác port name tự động detect
     */
    MainModel::instance()->initSerialReceiver();

    QQmlApplicationEngine engine;

    /*
     * Expose SerialReceiver cho QML để kết nối signal trực tiếp
     * với TellTalesModel và MediaPlayerModel
     */
    engine.rootContext()->setContextProperty(
        "serialReceiver", MainModel::instance()->serialReceiver());

    const QUrl url(QStringLiteral("qrc:/main.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject *obj, const QUrl &objUrl) {
        if (!obj && url == objUrl)
            QCoreApplication::exit(-1);
    }, Qt::QueuedConnection);
    engine.load(url);

    return app.exec();
}
