#include "serialreceiver.h"
#include <QDebug>

SerialReceiver::SerialReceiver(QObject *parent)
    : QObject(parent)
    , m_serial(new QSerialPort(this))
    , m_reconnectTimer(new QTimer(this))
    , m_connected(false)
    , m_hardwareMode(false)
{
    /* Cấu hình serial mặc định: 115200 8N1 (giống firmware STM32) */
    m_serial->setBaudRate(QSerialPort::Baud115200);
    m_serial->setDataBits(QSerialPort::Data8);
    m_serial->setParity(QSerialPort::NoParity);
    m_serial->setStopBits(QSerialPort::OneStop);
    m_serial->setFlowControl(QSerialPort::NoFlowControl);

    connect(m_serial, &QSerialPort::readyRead,
            this, &SerialReceiver::onReadyRead);
    connect(m_serial, &QSerialPort::errorOccurred,
            this, &SerialReceiver::onSerialError);

    /* Timer tự động reconnect mỗi 3 giây nếu mất kết nối */
    m_reconnectTimer->setInterval(3000);
    connect(m_reconnectTimer, &QTimer::timeout,
            this, &SerialReceiver::onReconnectTimer);
}

SerialReceiver::~SerialReceiver()
{
    disconnect();
}

/* ============ Properties ============ */

QString SerialReceiver::portName() const
{
    return m_portName;
}

void SerialReceiver::setPortName(const QString &name)
{
    if (m_portName != name) {
        m_portName = name;
        emit portNameChanged();
    }
}

bool SerialReceiver::isConnected() const
{
    return m_connected;
}

bool SerialReceiver::hardwareMode() const
{
    return m_hardwareMode;
}

void SerialReceiver::setHardwareMode(bool enabled)
{
    if (m_hardwareMode != enabled) {
        m_hardwareMode = enabled;
        emit hardwareModeChanged();

        if (enabled) {
            autoConnect();
        } else {
            disconnect();
        }
    }
}

/* ============ Auto-detect & Connect ============ */

QStringList SerialReceiver::availablePorts() const
{
    QStringList list;
    const auto ports = QSerialPortInfo::availablePorts();
    for (const QSerialPortInfo &info : ports) {
        list << QString("%1 - %2 [%3:%4]")
                    .arg(info.portName())
                    .arg(info.description())
                    .arg(info.vendorIdentifier(), 4, 16, QChar('0'))
                    .arg(info.productIdentifier(), 4, 16, QChar('0'));
    }
    return list;
}

bool SerialReceiver::autoConnect()
{
    /* Nếu đang kết nối, đóng trước */
    if (m_serial->isOpen()) {
        m_serial->close();
    }

    const auto ports = QSerialPortInfo::availablePorts();

    /*
     * Chiến lược tìm port:
     * 1. Trên Raspberry Pi: ưu tiên /dev/ttyAMA0 hoặc /dev/ttyS0 (UART hardware)
     * 2. Trên PC: tìm USB-TTL phổ biến (CP2102, CH340, FTDI)
     * 3. Fallback: thử port đầu tiên có sẵn
     */

    /* Ưu tiên 1: Raspberry Pi native UART */
    for (const QSerialPortInfo &info : ports) {
        if (info.portName().contains("ttyAMA") || info.portName().contains("ttyS0")) {
            if (tryOpenPort(info.portName())) {
                qDebug() << "[SerialReceiver] Connected to Pi UART:" << info.portName();
                return true;
            }
        }
    }

    /* Ưu tiên 2: USB-TTL adapters (CP2102, CH340, FTDI) */
    const QStringList usbKeywords = {
        "CP210", "CH340", "CH341", "FTDI", "FT232",
        "USB-SERIAL", "USB Serial", "Silicon Labs",
        "USB2.0-Ser", "ttyUSB"
    };

    for (const QSerialPortInfo &info : ports) {
        QString desc = info.description().toUpper();
        QString mfr  = info.manufacturer().toUpper();
        for (const QString &kw : usbKeywords) {
            if (desc.contains(kw.toUpper()) || mfr.contains(kw.toUpper())
                || info.portName().contains(kw, Qt::CaseInsensitive)) {
                if (tryOpenPort(info.portName())) {
                    qDebug() << "[SerialReceiver] Connected to USB-TTL:" << info.portName()
                             << "-" << info.description();
                    return true;
                }
            }
        }
    }

    /* Ưu tiên 3: Nếu có chỉ định portName cụ thể */
    if (!m_portName.isEmpty()) {
        if (tryOpenPort(m_portName)) {
            qDebug() << "[SerialReceiver] Connected to specified port:" << m_portName;
            return true;
        }
    }

    /* Không tìm thấy → bật reconnect timer */
    qWarning() << "[SerialReceiver] No STM32 port found. Retrying in 3s...";
    qWarning() << "[SerialReceiver] Available ports:" << availablePorts();
    m_reconnectTimer->start();
    return false;
}

void SerialReceiver::disconnect()
{
    m_reconnectTimer->stop();
    if (m_serial->isOpen()) {
        m_serial->close();
    }
    if (m_connected) {
        m_connected = false;
        emit connectedChanged();
        qDebug() << "[SerialReceiver] Disconnected";
    }
}

/* ============ Data Reception ============ */

void SerialReceiver::onReadyRead()
{
    m_buffer.append(m_serial->readAll());

    /*
     * Tách từng dòng kết thúc bằng '\n'
     * Firmware gửi: "DATA:speed=64,...\n" hoặc "BTN:left_signal=ON\n"
     */
    while (m_buffer.contains('\n')) {
        int idx = m_buffer.indexOf('\n');
        QByteArray line = m_buffer.left(idx).trimmed();
        m_buffer.remove(0, idx + 1);

        if (!line.isEmpty()) {
            processLine(line);
        }
    }

    /* Bảo vệ: nếu buffer quá lớn (>2KB), xóa bỏ */
    if (m_buffer.size() > 2048) {
        m_buffer.clear();
    }
}

void SerialReceiver::processLine(const QByteArray &line)
{
    if (line.startsWith("DATA:")) {
        parseDataFrame(line.mid(5));  /* Bỏ prefix "DATA:" */
    } else if (line.startsWith("BTN:")) {
        parseButtonFrame(line.mid(4)); /* Bỏ prefix "BTN:" */
    }
    /* Bỏ qua các dòng khác (boot message, debug, etc.) */
}

/**
 * @brief Parse DATA frame: "speed=64,rpm=2240,fuel=75,batt=80,gear=D"
 */
void SerialReceiver::parseDataFrame(const QByteArray &payload)
{
    const QList<QByteArray> pairs = payload.split(',');

    for (const QByteArray &pair : pairs) {
        int eq = pair.indexOf('=');
        if (eq < 0) continue;

        QByteArray key = pair.left(eq).trimmed();
        QByteArray val = pair.mid(eq + 1).trimmed();

        if (key == "speed") {
            emit speedReceived(val.toInt());
        } else if (key == "rpm") {
            emit rpmReceived(val.toInt());
        } else if (key == "fuel") {
            /* Firmware gửi 0-100, Dashboard cần 0.0-1.0 */
            emit fuelLevelReceived(val.toFloat() / 100.0f);
        } else if (key == "batt") {
            emit batteryLevelReceived(val.toFloat() / 100.0f);
        } else if (key == "gear") {
            emit gearReceived(QString::fromUtf8(val));
        }
    }
}

/**
 * @brief Parse BTN frame: "left_signal=ON" hoặc "media_play=ON"
 */
void SerialReceiver::parseButtonFrame(const QByteArray &payload)
{
    int eq = payload.indexOf('=');
    if (eq < 0) return;

    QByteArray name  = payload.left(eq).trimmed();
    QByteArray state = payload.mid(eq + 1).trimmed();
    bool active = (state == "ON");

    /* Emit generic signal */
    emit buttonEvent(QString::fromUtf8(name), active);

    /* Emit specific signals cho từng nút → mapping trực tiếp với TellTalesModel */
    if (name == "left_signal") {
        emit turnLeftChanged(active);
    } else if (name == "right_signal") {
        emit turnRightChanged(active);
    } else if (name == "beam") {
        emit beamChanged(active);
    } else if (name == "high_beams") {
        emit highBeamsChanged(active);
    } else if (name == "parked") {
        emit parkedChanged(active);
    } else if (name == "airbag") {
        emit airbagChanged(active);
    } else if (name == "media_play") {
        emit mediaPlayToggled();
    } else if (name == "media_next") {
        emit mediaNextTriggered();
    }
}

/* ============ Error Handling & Reconnect ============ */

void SerialReceiver::onSerialError(QSerialPort::SerialPortError error)
{
    if (error == QSerialPort::NoError) return;

    QString errMsg;
    switch (error) {
    case QSerialPort::DeviceNotFoundError:
        errMsg = "Device not found"; break;
    case QSerialPort::PermissionError:
        errMsg = "Permission denied (port busy?)"; break;
    case QSerialPort::ResourceError:
        errMsg = "Device disconnected"; break;
    default:
        errMsg = QString("Serial error code: %1").arg(error); break;
    }

    qWarning() << "[SerialReceiver] Error:" << errMsg;
    emit serialError(errMsg);

    /* Nếu bị ngắt kết nối, cập nhật state và bật reconnect */
    if (m_connected && !m_serial->isOpen()) {
        m_connected = false;
        emit connectedChanged();
        if (m_hardwareMode) {
            m_reconnectTimer->start();
        }
    }
}

void SerialReceiver::onReconnectTimer()
{
    if (m_connected) {
        m_reconnectTimer->stop();
        return;
    }
    qDebug() << "[SerialReceiver] Attempting reconnect...";
    if (autoConnect()) {
        m_reconnectTimer->stop();
    }
}

/* ============ Internal ============ */

bool SerialReceiver::tryOpenPort(const QString &portName)
{
    m_serial->setPortName(portName);
    if (m_serial->open(QIODevice::ReadOnly)) {
        m_portName = portName;
        m_connected = true;
        m_buffer.clear();
        emit portNameChanged();
        emit connectedChanged();
        return true;
    }
    return false;
}
