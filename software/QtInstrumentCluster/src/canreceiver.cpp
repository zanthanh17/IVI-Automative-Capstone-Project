#include "canreceiver.h"

#include <QByteArray>
#include <QDebug>
#include <QDir>
#include <QFileInfo>
#include <QtGlobal>

#ifdef Q_OS_LINUX
#include <cerrno>
#include <cstring>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>
#include <linux/can.h>
#include <linux/can/raw.h>
#include <linux/if.h>
#endif

namespace {
constexpr quint32 CanIdVehicleTelemetry = 0x100U;
constexpr quint32 CanIdButtonState = 0x101U;
constexpr quint32 CanIdButtonEvent = 0x102U;
constexpr quint32 CanIdBodyStatus = 0x201U;

float percentToLevel(quint8 percent)
{
    if (percent > 100U)
        percent = 100U;
    return static_cast<float>(percent) / 100.0f;
}
}

CanReceiver::CanReceiver(QObject *parent)
    : QObject(parent)
    , m_interfaceName(qEnvironmentVariable("IVI_CAN_IFACE", QStringLiteral("can0")).trimmed())
    , m_connected(false)
    , m_hardwareMode(!qEnvironmentVariableIntValue("IVI_CAN_DISABLE"))
    , m_socketFd(-1)
    , m_notifier(nullptr)
    , m_reconnectTimer(new QTimer(this))
{
    if (m_interfaceName.isEmpty())
        m_interfaceName = QStringLiteral("can0");

    m_reconnectTimer->setInterval(2000);
    connect(m_reconnectTimer, &QTimer::timeout, this, &CanReceiver::onReconnectTimer);
}

CanReceiver::~CanReceiver()
{
    disconnect();
}

QString CanReceiver::interfaceName() const
{
    return m_interfaceName;
}

void CanReceiver::setInterfaceName(const QString &name)
{
    const QString normalized = name.trimmed();
    if (normalized.isEmpty() || normalized == m_interfaceName)
        return;

    const bool wasConnected = m_connected;
    disconnect();
    m_interfaceName = normalized;
    emit interfaceNameChanged();

    if (wasConnected || m_hardwareMode)
        autoConnect();
}

bool CanReceiver::isConnected() const
{
    return m_connected;
}

bool CanReceiver::hardwareMode() const
{
    return m_hardwareMode;
}

void CanReceiver::setHardwareMode(bool enabled)
{
    if (m_hardwareMode == enabled)
        return;

    m_hardwareMode = enabled;
    emit hardwareModeChanged();

    if (enabled)
        autoConnect();
    else
        disconnect();
}

bool CanReceiver::autoConnect()
{
    if (!m_hardwareMode)
        return false;

#ifdef Q_OS_LINUX
    closeSocket();

    const QByteArray ifName = m_interfaceName.toLocal8Bit();
    if (ifName.isEmpty() || ifName.size() >= IFNAMSIZ) {
        emit canError(QStringLiteral("Invalid CAN interface name: %1").arg(m_interfaceName));
        return false;
    }

    const int fd = ::socket(PF_CAN, SOCK_RAW | SOCK_NONBLOCK, CAN_RAW);
    if (fd < 0) {
        emit canError(QStringLiteral("Cannot create CAN socket: %1").arg(QString::fromLocal8Bit(std::strerror(errno))));
        return false;
    }

    struct ifreq ifr;
    std::memset(&ifr, 0, sizeof(ifr));
    std::strncpy(ifr.ifr_name, ifName.constData(), IFNAMSIZ - 1);

    if (::ioctl(fd, SIOCGIFINDEX, &ifr) < 0) {
        const QString error = QStringLiteral("CAN interface %1 not found: %2")
                                  .arg(m_interfaceName, QString::fromLocal8Bit(std::strerror(errno)));
        ::close(fd);
        emit canError(error);
        if (!m_reconnectTimer->isActive())
            m_reconnectTimer->start();
        return false;
    }

    struct sockaddr_can addr;
    std::memset(&addr, 0, sizeof(addr));
    addr.can_family = AF_CAN;
    addr.can_ifindex = ifr.ifr_ifindex;

    if (::bind(fd, reinterpret_cast<struct sockaddr *>(&addr), sizeof(addr)) < 0) {
        const QString error = QStringLiteral("Cannot bind %1: %2")
                                  .arg(m_interfaceName, QString::fromLocal8Bit(std::strerror(errno)));
        ::close(fd);
        emit canError(error);
        if (!m_reconnectTimer->isActive())
            m_reconnectTimer->start();
        return false;
    }

    m_socketFd = fd;
    m_notifier = new QSocketNotifier(m_socketFd, QSocketNotifier::Read, this);
    connect(m_notifier, &QSocketNotifier::activated, this, &CanReceiver::onReadyRead);

    m_connected = true;
    m_reconnectTimer->stop();
    emit connectedChanged();
    qInfo() << "[CanReceiver] Connected to SocketCAN interface:" << m_interfaceName;
    return true;
#else
    emit canError(QStringLiteral("SocketCAN is only supported on Linux."));
    return false;
#endif
}

void CanReceiver::disconnect()
{
    m_reconnectTimer->stop();
    closeSocket();
}

QStringList CanReceiver::availableInterfaces() const
{
    QStringList interfaces;

#ifdef Q_OS_LINUX
    const QDir netDir(QStringLiteral("/sys/class/net"));
    const QFileInfoList entries = netDir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QFileInfo &entry : entries) {
        const QString name = entry.fileName();
        if (name.startsWith(QStringLiteral("can")) || name.startsWith(QStringLiteral("vcan")))
            interfaces << name;
    }
#endif

    return interfaces;
}

void CanReceiver::onReadyRead()
{
#ifdef Q_OS_LINUX
    while (m_socketFd >= 0) {
        struct can_frame frame;
        const ssize_t nbytes = ::read(m_socketFd, &frame, sizeof(frame));
        if (nbytes < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK)
                return;

            emit canError(QStringLiteral("CAN read failed: %1").arg(QString::fromLocal8Bit(std::strerror(errno))));
            closeSocket();
            if (m_hardwareMode)
                m_reconnectTimer->start();
            return;
        }

        if (nbytes != static_cast<ssize_t>(sizeof(frame)))
            continue;

        if ((frame.can_id & CAN_EFF_FLAG) != 0U || (frame.can_id & CAN_RTR_FLAG) != 0U)
            continue;

        const quint32 frameId = frame.can_id & CAN_SFF_MASK;
        const QByteArray payload(reinterpret_cast<const char *>(frame.data), qMin<int>(frame.can_dlc, 8));
        processFrame(frameId, payload);
    }
#endif
}

void CanReceiver::onReconnectTimer()
{
    if (!m_connected)
        autoConnect();
}

void CanReceiver::closeSocket()
{
#ifdef Q_OS_LINUX
    if (m_notifier) {
        m_notifier->setEnabled(false);
        m_notifier->deleteLater();
        m_notifier = nullptr;
    }

    if (m_socketFd >= 0) {
        ::close(m_socketFd);
        m_socketFd = -1;
    }
#endif

    if (m_connected) {
        m_connected = false;
        emit connectedChanged();
        qInfo() << "[CanReceiver] Disconnected";
    }
}

void CanReceiver::processFrame(quint32 frameId, const QByteArray &payload)
{
    switch (frameId) {
    case CanIdVehicleTelemetry:
        processTelemetryFrame(payload);
        break;
    case CanIdButtonState:
        processButtonStateFrame(payload);
        break;
    case CanIdButtonEvent:
        processButtonEventFrame(payload);
        break;
    case CanIdBodyStatus:
        processBodyStatusFrame(payload);
        break;
    default:
        break;
    }
}

void CanReceiver::processTelemetryFrame(const QByteArray &payload)
{
    if (payload.size() < 8)
        return;

    const auto byteAt = [&payload](int index) -> quint8 {
        return static_cast<quint8>(payload.at(index));
    };

    const int speed = (static_cast<int>(byteAt(0)) << 8) | static_cast<int>(byteAt(1));
    const int rpm = (static_cast<int>(byteAt(2)) << 8) | static_cast<int>(byteAt(3));
    const QString gear = QString(QChar::fromLatin1(static_cast<char>(byteAt(6))));

    emit speedReceived(speed);
    emit rpmReceived(rpm);
    emit fuelLevelReceived(percentToLevel(byteAt(4)));
    emit batteryLevelReceived(percentToLevel(byteAt(5)));
    emit gearReceived(gear);
}

void CanReceiver::processButtonStateFrame(const QByteArray &payload)
{
    if (payload.size() < 2)
        return;

    const quint8 mask = static_cast<quint8>(payload.at(0));
    emitButtonSignal(1U, (mask & (1U << 0)) != 0U, false);
    emitButtonSignal(2U, (mask & (1U << 1)) != 0U, false);
    emitButtonSignal(3U, (mask & (1U << 2)) != 0U, false);
    emitButtonSignal(4U, (mask & (1U << 3)) != 0U, false);
    emitButtonSignal(5U, (mask & (1U << 4)) != 0U, false);
    emitButtonSignal(6U, (mask & (1U << 5)) != 0U, false);
    emitButtonSignal(7U, (mask & (1U << 6)) != 0U, false);

    const bool driveMode = static_cast<quint8>(payload.at(1)) != 0U;
    emit gearReceived(driveMode ? QStringLiteral("D") : QStringLiteral("P"));
}

void CanReceiver::processButtonEventFrame(const QByteArray &payload)
{
    if (payload.size() < 2)
        return;

    const quint8 buttonId = static_cast<quint8>(payload.at(0));
    const bool active = static_cast<quint8>(payload.at(1)) != 0U;
    emitButtonSignal(buttonId, active, true);
}

void CanReceiver::processBodyStatusFrame(const QByteArray &payload)
{
    if (payload.size() < 4)
        return;

    const auto byteAt = [&payload](int index) -> quint8 {
        return static_cast<quint8>(payload.at(index));
    };

    const int commandMask = static_cast<int>(byteAt(0));
    const int outputMask = static_cast<int>(byteAt(1));
    const int flags = static_cast<int>(byteAt(2));
    const int counter = static_cast<int>(byteAt(3));

    emit bodyStatusReceived(commandMask, outputMask, flags, counter);
    emit bodyRxTimeoutChanged((flags & (1U << 1)) != 0U);
}

void CanReceiver::emitButtonSignal(quint8 buttonId, bool active, bool triggerMedia)
{
    const QString name = buttonName(buttonId);
    if (!name.isEmpty())
        emit buttonEvent(name, active);

    switch (buttonId) {
    case 1U:
        emit turnLeftChanged(active);
        break;
    case 2U:
        emit turnRightChanged(active);
        break;
    case 3U:
        emit beamChanged(active);
        break;
    case 4U:
        emit highBeamsChanged(active);
        break;
    case 5U:
        emit parkedChanged(active);
        break;
    case 6U:
        emit airbagChanged(active);
        break;
    case 7U:
        emit hornChanged(active);
        break;
    case 8U:
        if (triggerMedia)
            emit mediaNextTriggered();
        break;
    default:
        break;
    }
}

QString CanReceiver::buttonName(quint8 buttonId) const
{
    switch (buttonId) {
    case 1U: return QStringLiteral("left_signal");
    case 2U: return QStringLiteral("right_signal");
    case 3U: return QStringLiteral("beam");
    case 4U: return QStringLiteral("high_beams");
    case 5U: return QStringLiteral("parked");
    case 6U: return QStringLiteral("airbag");
    case 7U: return QStringLiteral("horn");
    case 8U: return QStringLiteral("media_next");
    default: return QString();
    }
}
