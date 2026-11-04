#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

class QLocalServer;

// Keeps one running copy of the app per user. A second launch connects to the
// first copy's local socket ($XDG_RUNTIME_DIR/TunedChaos.sock), which
// then emits activationRequested() to bring its window forward, and
// openRequested() with the files the second launch was asked to open.
class SingleInstance : public QObject
{
    Q_OBJECT

public:
    explicit SingleInstance(QObject *parent);
    ~SingleInstance() override;

    // Returns false when another copy is already running (it has been asked
    // to come to the front) and this process should exit.
    // `files`: what this launch was asked to open (handed to the running copy).
    bool start(const QStringList &files = {});
    // Stops answering (a restart: the new copy must not find this one).
    void stop();

signals:
    void activationRequested();
    void openRequested(const QStringList &files);

private:
    QString m_socketPath;
    QLocalServer *m_server = nullptr;
};
