#include "livecameraitem.h"
#include <QPainter>
#include <QStandardPaths>
#include <QtEndian>
#include <QJsonObject>
#include <QJsonDocument>
#include <QCoreApplication>

LiveCameraItem::LiveCameraItem(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    m_socket = new QLocalSocket(this);
    m_reconnectTimer = new QTimer(this);
    m_reconnectTimer->setInterval(2000);

    connect(m_socket, &QLocalSocket::readyRead, this, &LiveCameraItem::onReadyRead);
#if QT_VERSION >= QT_VERSION_CHECK(5, 15, 0)
    connect(m_socket, &QLocalSocket::errorOccurred, this, &LiveCameraItem::onSocketError);
#else
    connect(m_socket, QOverload<QLocalSocket::LocalSocketError>::of(&QLocalSocket::error), this, &LiveCameraItem::onSocketError);
#endif

    connect(m_socket, &QLocalSocket::connected, this, [this]() {
        QJsonObject req;
        req["cmd"] = "stream";
        QJsonDocument doc(req);
        m_socket->write(doc.toJson(QJsonDocument::Compact) + "\n");
        m_running = true;
        emit runningChanged();
    });

    connect(m_socket, &QLocalSocket::disconnected, this, [this]() {
        m_running = false;
        emit runningChanged();
        if (isVisible()) {
            m_reconnectTimer->start();
        }
    });

    connect(m_reconnectTimer, &QTimer::timeout, this, &LiveCameraItem::connectToDaemon);

    connect(this, &QQuickItem::visibleChanged, this, [this]() {
        if (isVisible()) {
            startStream();
        } else {
            stopStream();
        }
    });
}

LiveCameraItem::~LiveCameraItem()
{
}

void LiveCameraItem::startStream()
{
    if (m_socket->state() == QLocalSocket::UnconnectedState) {
        connectToDaemon();
    }
}

void LiveCameraItem::stopStream()
{
    m_reconnectTimer->stop();
    m_socket->disconnectFromServer();
    m_buffer.clear();
}

void LiveCameraItem::connectToDaemon()
{
    QString socketPath = qEnvironmentVariable("DROWSY_DAEMON_SOCKET");
    if (socketPath.isEmpty()) {
        QString runtimeDir = qEnvironmentVariable("XDG_RUNTIME_DIR");
        if (runtimeDir.isEmpty()) {
            runtimeDir = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
        }
        if (runtimeDir.isEmpty()) {
            runtimeDir = "/tmp";
        }
        socketPath = runtimeDir + "/drowsy-camera-daemon.sock";
    }

    if (m_socket->state() == QLocalSocket::UnconnectedState) {
        m_socket->connectToServer(socketPath);
    }
}

void LiveCameraItem::onSocketError(QLocalSocket::LocalSocketError error)
{
    Q_UNUSED(error);
    m_socket->disconnectFromServer();
    if (isVisible()) {
        m_reconnectTimer->start();
    }
}

void LiveCameraItem::onReadyRead()
{
    m_buffer.append(m_socket->readAll());

    while (m_buffer.size() >= 8) {
        if (!m_buffer.startsWith("FRAM")) {
            int idx = m_buffer.indexOf("FRAM");
            if (idx == -1) {
                m_buffer.clear();
                return;
            }
            m_buffer.remove(0, idx);
            if (m_buffer.size() < 8) return;
        }

        quint32 payloadSize;
        memcpy(&payloadSize, m_buffer.constData() + 4, 4);
        payloadSize = qFromLittleEndian(payloadSize);

        if (static_cast<quint32>(m_buffer.size()) < 8 + payloadSize) {
            return;
        }

        QByteArray jpeg = m_buffer.mid(8, payloadSize);
        m_buffer.remove(0, 8 + payloadSize);

        if (m_currentImage.loadFromData(jpeg, "JPG")) {
            update();
        }
    }
}

void LiveCameraItem::paint(QPainter *painter)
{
    if (!m_currentImage.isNull()) {
        QImage scaled = m_currentImage.scaled(boundingRect().size().toSize(), 
                                              Qt::KeepAspectRatioByExpanding, 
                                              Qt::SmoothTransformation);
        int x = (boundingRect().width() - scaled.width()) / 2;
        int y = (boundingRect().height() - scaled.height()) / 2;
        painter->drawImage(x, y, scaled);
    } else {
        painter->fillRect(boundingRect(), Qt::black);
    }
}
