#ifndef SERIALRECEIVER_H
#define SERIALRECEIVER_H

#include <QObject>
#include <QSerialPort>
#include <QSerialPortInfo>
#include <QTimer>
#include <QByteArray>

/**
 * @brief SerialReceiver - Nhận dữ liệu UART từ STM32 firmware
 *
 * Kiến trúc linh hoạt:
 *   - Trên PC host:  STM32 → USB-TTL (CP2102/CH340) → COMx    → Qt SerialReceiver
 *   - Trên Raspberry Pi: telemetry ưu tiên CAN; Pi UART (/dev/ttyAMA0) dành cho GPS/gpsd
 *
 * Giao thức firmware gửi:
 *   DATA:speed=<0-200>,rpm=<0-7000>,fuel=<0-100>,batt=<0-100>,gear=<P|D>\n
 *   BTN:<name>=<ON|OFF>\n
 *
 * SerialReceiver parse và emit signal để cập nhật Dashboard UI models.
 */
class SerialReceiver : public QObject
{
    Q_OBJECT

    /** Port name hiển thị cho QML (auto-detect hoặc chỉ định) */
    Q_PROPERTY(QString portName READ portName WRITE setPortName NOTIFY portNameChanged)

    /** Trạng thái kết nối */
    Q_PROPERTY(bool connected READ isConnected NOTIFY connectedChanged)

    /** Cho phép bật/tắt nguồn dữ liệu từ phần cứng */
    Q_PROPERTY(bool hardwareMode READ hardwareMode WRITE setHardwareMode NOTIFY hardwareModeChanged)

public:
    explicit SerialReceiver(QObject *parent = nullptr);
    ~SerialReceiver();

    QString portName() const;
    void setPortName(const QString &name);

    bool isConnected() const;

    bool hardwareMode() const;
    void setHardwareMode(bool enabled);

    /** Tự động tìm và mở port STM32 (USB-TTL hoặc IVI_SERIAL_PORT nếu chỉ định) */
    Q_INVOKABLE bool autoConnect();

    /** Đóng kết nối serial */
    Q_INVOKABLE void disconnect();

    /** Liệt kê tất cả serial ports có sẵn */
    Q_INVOKABLE QStringList availablePorts() const;

signals:
    void portNameChanged();
    void connectedChanged();
    void hardwareModeChanged();

    /* === Sensor Data signals (từ DATA: frame) === */
    void speedReceived(int speed);        // 0-200 km/h
    void rpmReceived(int rpm);            // 0-7000
    void fuelLevelReceived(float level);  // 0.0-1.0
    void batteryLevelReceived(float level); // 0.0-1.0
    void gearReceived(QString gear);      // "P", "D", "R", "N"

    /* === Button Event signals (từ BTN: frame) === */
    void buttonEvent(QString name, bool state);

    /* === Specific button signals cho tiện QML binding === */
    void turnLeftChanged(bool active);
    void turnRightChanged(bool active);
    void beamChanged(bool active);
    void highBeamsChanged(bool active);
    void parkedChanged(bool active);
    void airbagChanged(bool active);
    void hornChanged(bool active);
    void mediaPlayToggled();
    void mediaNextTriggered();

    /* === Connection status === */
    void serialError(QString errorMessage);

private slots:
    void onReadyRead();
    void onSerialError(QSerialPort::SerialPortError error);
    void onReconnectTimer();

private:
    void processLine(const QByteArray &line);
    void parseDataFrame(const QByteArray &payload);
    void parseButtonFrame(const QByteArray &payload);
    bool tryOpenPort(const QString &portName);

    QSerialPort *m_serial;
    QTimer *m_reconnectTimer;
    QByteArray m_buffer;
    QString m_portName;
    bool m_connected;
    bool m_hardwareMode;
};

#endif // SERIALRECEIVER_H
