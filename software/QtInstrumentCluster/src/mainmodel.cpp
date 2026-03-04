#include "mainmodel.h"
#include "serialreceiver.h"
#include <QDebug>

MainModel::MainModel(QObject* parent)
    : QObject(parent)
    , m_speed(0)
    , m_rpm(0)
    , m_odo(0)
    , m_range(0)
    , m_fuelLevel(0.2f)
    , m_batteryLevel(0.2f)
    , m_gearText("P")
    , m_serialReceiver(nullptr)
{}

MainModel* MainModel::instance()
{
    static MainModel* s_instance = nullptr;
    if (!s_instance)
        s_instance = new MainModel();
    return s_instance;
}

float MainModel::speed() const       { return m_speed; }
float MainModel::rpm() const         { return m_rpm; }
float MainModel::odo() const         { return m_odo; }
float MainModel::range() const       { return m_range; }
float MainModel::fuelLevel() const   { return m_fuelLevel; }
float MainModel::batteryLevel() const { return m_batteryLevel; }
QString MainModel::gearText() const  { return m_gearText; }

bool MainModel::hardwareConnected() const
{
    return m_serialReceiver && m_serialReceiver->isConnected();
}

void MainModel::setSpeed(float newValue) {
    if (m_speed != newValue) {
        m_speed = newValue;
        emit speedChanged();
    }
}

void MainModel::setRPM(float newValue) {
    if (m_rpm != newValue) {
        m_rpm = newValue;
        emit rpmChanged();
    }
}

void MainModel::setOdo(float newValue) {
    if (m_odo != newValue) {
        m_odo = newValue;
        emit odoChanged();
    }
}

void MainModel::setRange(float newValue) {
    if (m_range != newValue) {
        m_range = newValue;
        emit rangeChanged();
    }
}

void MainModel::setFuelLevel(float newValue) {
    if (m_fuelLevel != newValue) {
        m_fuelLevel = newValue;
        emit fuelLevelChanged();
    }
}

void MainModel::setBatteryLevel(float newValue) {
    if (m_batteryLevel != newValue) {
        m_batteryLevel = newValue;
        emit batteryLevelChanged();
    }
}

void MainModel::setGearText(const QString &text) {
    if (m_gearText != text) {
        m_gearText = text;
        emit gearTextChanged();
    }
}

SerialReceiver* MainModel::serialReceiver() const
{
    return m_serialReceiver;
}

void MainModel::initSerialReceiver()
{
    if (m_serialReceiver) return;

    m_serialReceiver = new SerialReceiver(this);

    /*
     * Kết nối signals từ SerialReceiver → MainModel
     * Khi nhận DATA frame từ STM32, cập nhật properties và emit modelUpdated()
     */
    connect(m_serialReceiver, &SerialReceiver::speedReceived, this, [this](int speed) {
        setSpeed(static_cast<float>(speed));
        emit modelUpdated();
    });

    connect(m_serialReceiver, &SerialReceiver::rpmReceived, this, [this](int rpm) {
        setRPM(static_cast<float>(rpm));
        emit modelUpdated();
    });

    connect(m_serialReceiver, &SerialReceiver::fuelLevelReceived, this, [this](float level) {
        setFuelLevel(level);
        emit modelUpdated();
    });

    connect(m_serialReceiver, &SerialReceiver::batteryLevelReceived, this, [this](float level) {
        setBatteryLevel(level);
        emit modelUpdated();
    });

    connect(m_serialReceiver, &SerialReceiver::gearReceived, this, [this](QString gear) {
        setGearText(gear);
        emit modelUpdated();
    });

    connect(m_serialReceiver, &SerialReceiver::connectedChanged, this, [this]() {
        emit hardwareConnectedChanged();
        if (m_serialReceiver->isConnected()) {
            qDebug() << "[MainModel] Hardware connected, simulation data will be ignored";
        }
    });

    qDebug() << "[MainModel] SerialReceiver initialized, attempting auto-connect...";
    m_serialReceiver->setHardwareMode(true);
}
