#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QFontDatabase>
#include <QFont>
#include <QQuickWindow>
#include <QLocale>
#include <QTranslator>

#ifdef HAS_WEBENGINE_MAP
#include <QtWebEngine/qtwebengineglobal.h>
#endif

#include "src/externalmediacontroller.h"
#include "src/bluetoothcontroller.h"
#include "src/mainmodel.h"
#include "src/serialreceiver.h"
#include "src/weatherprovider.h"
#include "src/osrmrouteprovider.h"
#include "src/systemsettingscontroller.h"

int main(int argc, char *argv[])
{
#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
    QCoreApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
#endif

    qputenv("QTWEBENGINEPROCESS_PATH", "/usr/lib/x86_64-linux-gnu/qt5/libexec/QtWebEngineProcess");

    /*
     * Mapbox GL plugin requires the basic render loop (single-threaded).
     * Without this, the plugin warns "Threaded rendering is not optimal"
     * and QSGTextureAtlas allocation can fail (code=501).
     */
    qputenv("QSG_RENDER_LOOP", "basic");

    /* Disable QSG texture atlas to avoid GL_STACK_OVERFLOW (501) on Intel GPUs */
    qputenv("QSG_NO_ATLAS_TEXTURES", "1");

    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);


#ifdef HAS_WEBENGINE_MAP
    QtWebEngine::initialize();
#endif

    QGuiApplication app(argc, argv);

    int fontId = QFontDatabase::addApplicationFont(":/fonts/Inter-Regular.ttf");
    if (fontId != -1) {
        QString family = QFontDatabase::applicationFontFamilies(fontId).at(0);
        app.setFont(QFont(family));
    }

    QTranslator translator;
    const QStringList uiLanguages = QLocale::system().uiLanguages();
    for (const QString &locale : uiLanguages) {
        const QString baseName = "QtInstrumentCluster_" + QLocale(locale).name();
        if (translator.load(":/i18n/" + baseName)) {
            app.installTranslator(&translator);
            break;
        }
    }

    qmlRegisterSingletonType<MainModel>("MainModelData", 1, 0, "MainModelData", [](QQmlEngine*, QJSEngine*) -> QObject* {
            return MainModel::instance();
        });

    qmlRegisterSingletonType(QUrl("qrc:///models/TellTalesModel.qml"), "TellTalesModel", 1, 0, "TellTalesModel");
    qmlRegisterSingletonType(QUrl("qrc:///models/MainModel.qml"), "MainModel", 1, 0, "MainModel");
    qmlRegisterSingletonType(QUrl("qrc:///models/Style.qml"), "Style", 1, 0, "Style");
    qmlRegisterSingletonType(QUrl("qrc:///models/Units.qml"), "Units", 1, 0, "Units");
    qmlRegisterSingletonType(QUrl("qrc:///models/NormalModeModel.qml"), "NormalModeModel", 1, 0, "NormalModeModel");
    qmlRegisterSingletonType(QUrl("qrc:///models/MediaPlayerModel.qml"), "MediaPlayerModel", 1, 0, "MediaPlayerModel");
    qmlRegisterSingletonType<BluetoothController>("BluetoothManager", 1, 0, "BluetoothManager",
        [](QQmlEngine*, QJSEngine*) -> QObject* {
            return BluetoothController::instance();
        });
    qmlRegisterSingletonType(QUrl("qrc:///models/NavigationFeed.qml"), "NavigationFeed", 1, 0, "NavigationFeed");
    qmlRegisterSingletonType(QUrl("qrc:///models/NavigationModel.qml"), "NavigationModel", 1, 0, "NavigationModel");

    qmlRegisterSingletonType<OsrmRouteProvider>("OsrmRoute", 1, 0, "OsrmRoute",
        [](QQmlEngine*, QJSEngine*) -> QObject* {
            return OsrmRouteProvider::instance();
        });

    qmlRegisterSingletonType<ExternalMediaController>("ExternalMedia", 1, 0, "ExternalMedia",
        [](QQmlEngine*, QJSEngine*) -> QObject* {
            return ExternalMediaController::instance();
        });

    qmlRegisterSingletonType<SystemSettingsController>("SystemSettings", 1, 0, "SystemSettings",
        [](QQmlEngine*, QJSEngine*) -> QObject* {
            return SystemSettingsController::instance();
        });

    QObject::connect(BluetoothController::instance(), &BluetoothController::deviceConnectionChanged,
                     ExternalMediaController::instance(),
                     [](const QString &, bool) {
        ExternalMediaController::instance()->rescan();
    });

    qmlRegisterSingletonType<WeatherProvider>("Weather", 1, 0, "Weather",
        [](QQmlEngine*, QJSEngine*) -> QObject* {
            return WeatherProvider::instance();
        });

    MainModel::instance()->initSerialReceiver();

    QQmlApplicationEngine engine;

    engine.rootContext()->setContextProperty(
        "serialReceiver", MainModel::instance()->serialReceiver());

    // Mapbox access token: read from environment variable MAPBOX_ACCESS_TOKEN
    // Set before running: export MAPBOX_ACCESS_TOKEN="pk.eyJ1..."
    QString mapboxToken = qEnvironmentVariable("MAPBOX_ACCESS_TOKEN", "");
    engine.rootContext()->setContextProperty("mapboxTokenFromEnv", mapboxToken);

    // Use Mapbox Directions when token is present; otherwise fallback to OSRM demo server.
    OsrmRouteProvider *routeProvider = OsrmRouteProvider::instance();
    if (!mapboxToken.trimmed().isEmpty()) {
        routeProvider->setProvider(QStringLiteral("mapbox"));
        routeProvider->setBaseUrl(QStringLiteral("https://api.mapbox.com"));
        routeProvider->setAccessToken(mapboxToken);
        routeProvider->setProfile(QStringLiteral("mapbox/driving-traffic"));
    } else {
        routeProvider->setProvider(QStringLiteral("osrm"));
        routeProvider->setBaseUrl(QStringLiteral("https://router.project-osrm.org"));
    }

    const QUrl url(QStringLiteral("qrc:/main.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject *obj, const QUrl &objUrl) {
        if (!obj && url == objUrl)
            QCoreApplication::exit(-1);
    }, Qt::QueuedConnection);
    engine.load(url);

    return app.exec();
}
