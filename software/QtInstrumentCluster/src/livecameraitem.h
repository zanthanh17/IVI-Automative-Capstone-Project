#pragma once

#include <QQuickPaintedItem>
#include <QImage>
#include <QLocalSocket>
#include <QTimer>

class LiveCameraItem : public QQuickPaintedItem
{
    Q_OBJECT
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
public:
    explicit LiveCameraItem(QQuickItem *parent = nullptr);
    ~LiveCameraItem() override;

    void paint(QPainter *painter) override;
    bool running() const { return m_running; }

public slots:
    void startStream();
    void stopStream();

signals:
    void runningChanged();

private slots:
    void onReadyRead();
    void onSocketError(QLocalSocket::LocalSocketError error);
    void connectToDaemon();

private:
    QLocalSocket *m_socket;
    QTimer *m_reconnectTimer;
    QImage m_currentImage;
    QByteArray m_buffer;
    bool m_running = false;
};
