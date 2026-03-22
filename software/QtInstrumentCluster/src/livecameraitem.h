#pragma once

#include <QQuickPaintedItem>
#include <QImage>
#include <QLocalSocket>
#include <QTimer>

class LiveCameraItem : public QQuickPaintedItem
{
    Q_OBJECT
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(bool hasFrames READ hasFrames NOTIFY hasFramesChanged)
public:
    explicit LiveCameraItem(QQuickItem *parent = nullptr);
    ~LiveCameraItem() override;

    void paint(QPainter *painter) override;
    bool running() const { return m_running; }
    bool hasFrames() const { return m_hasFrames; }

public slots:
    void startStream();
    void stopStream();

signals:
    void runningChanged();
    void hasFramesChanged();

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
    bool m_hasFrames = false;
};
