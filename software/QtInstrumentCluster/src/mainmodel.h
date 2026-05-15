#ifndef MAINMODEL_H
#define MAINMODEL_H

#include <QObject>

class CanReceiver;
class SerialReceiver;

class MainModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(float speed READ speed NOTIFY speedChanged)
    Q_PROPERTY(float rpm READ rpm NOTIFY rpmChanged)
    Q_PROPERTY(float odo READ odo WRITE setOdo NOTIFY odoChanged)
    Q_PROPERTY(float range READ range WRITE setRange NOTIFY rangeChanged)
    Q_PROPERTY(float fuelLevel READ fuelLevel NOTIFY fuelLevelChanged)
    Q_PROPERTY(float batteryLevel READ batteryLevel NOTIFY batteryLevelChanged)
    Q_PROPERTY(QString gearText READ gearText NOTIFY gearTextChanged)
    Q_PROPERTY(bool hardwareConnected READ hardwareConnected NOTIFY hardwareConnectedChanged)

public:
    static MainModel* instance();
    float speed() const;
    float rpm() const;
    float odo() const;
    float range() const;
    float fuelLevel() const;
    float batteryLevel() const;
    QString gearText() const;
    bool hardwareConnected() const;

    void setSpeed(float newValue);
    void setRPM(float newValue);
    Q_INVOKABLE void setOdo(float newValue);
    Q_INVOKABLE void setRange(float newValue);
    void setFuelLevel(float newValue);
    void setBatteryLevel(float newValue);
    void setGearText(const QString &text);

    /** Khởi tạo CAN receiver và SerialReceiver fallback */
    void initSerialReceiver();

    /** Trả về con trỏ SerialReceiver (để QML truy cập nếu cần) */
    SerialReceiver* serialReceiver() const;

    /** Trả về con trỏ CanReceiver (để QML truy cập nếu cần) */
    CanReceiver* canReceiver() const;

signals:
    void modelUpdated();
    void hardwareConnectedChanged();
    void speedChanged();
    void rpmChanged();
    void odoChanged();
    void rangeChanged();
    void fuelLevelChanged();
    void batteryLevelChanged();
    void gearTextChanged();

private:
    explicit MainModel(QObject* parent = nullptr);
    float m_speed;
    float m_rpm;
    float m_odo;
    float m_range;
    float m_fuelLevel;
    float m_batteryLevel;
    QString m_gearText;
    CanReceiver *m_canReceiver;
    SerialReceiver *m_serialReceiver;
};

#endif // MAINMODEL_H
