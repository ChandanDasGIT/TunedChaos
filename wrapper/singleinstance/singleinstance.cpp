#include "wrapper/singleinstance/singleinstance.h"

#include <QLocalServer>
#include <QLocalSocket>
#include <QUrl>
#include <QFileInfo>
#include <QStandardPaths>

namespace {

constexpr int ConnectTimeoutMs = 500;

} // namespace

SingleInstance::SingleInstance(QObject *parent)
    : QObject(parent)
{
}

SingleInstance::~SingleInstance()
{
    if (m_server)
        m_server->close(); // removes the socket file
}

void SingleInstance::stop()
{
    if (m_server) {
        m_server->close();
        delete m_server;
        m_server = nullptr;
    }
}

bool SingleInstance::start(const QStringList &files)
{
    m_socketPath = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation)
                   + QStringLiteral("/TunedChaos.sock");

    // Someone already listening? Ask them to come forward and step aside.
    QLocalSocket socket;
    socket.connectToServer(m_socketPath);
    if (socket.waitForConnected(ConnectTimeoutMs)) {
        // "activate", then a line per file to open (absolute: the other copy's
        // folder may differ)
        QByteArray message = "activate\n";
        for (const QString &file : files) {
            const QUrl url(file);
            message += (url.isLocalFile() ? url.toLocalFile() : QFileInfo(file).absoluteFilePath()).toUtf8() + '\n';
        }
        socket.write(message);
        socket.waitForBytesWritten(ConnectTimeoutMs);
        socket.disconnectFromServer();
        return false;
    }

    m_server = new QLocalServer(this);
    m_server->setSocketOptions(QLocalServer::UserAccessOption);
    if (!m_server->listen(m_socketPath)) {
        // Nobody answered above, so the socket file is left over from a crash.
        QLocalServer::removeServer(m_socketPath);
        if (!m_server->listen(m_socketPath)) {
            qWarning("Single instance: cannot listen on %s: %s", qPrintable(m_socketPath),
                     qPrintable(m_server->errorString()));
            return true; // run anyway, just without single-instance protection
        }
    }

    // Any connection is a second launch asking us to come forward.
    connect(m_server, &QLocalServer::newConnection, this, [this] {
        while (QLocalSocket *client = m_server->nextPendingConnection()) {
            // What it sends is read once it's done (it disconnects)
            const auto received = [this, client] {
                const QList<QByteArray> lines = client->readAll().split('\n');
                client->deleteLater();
                QStringList files;
                for (qsizetype i = 1; i < lines.size(); ++i) // (line 0: "activate")
                    if (!lines[i].isEmpty())
                        files << QString::fromUtf8(lines[i]);
                emit activationRequested();
                if (!files.isEmpty())
                    emit openRequested(files);
            };
            if (client->state() == QLocalSocket::UnconnectedState)
                received(); // (already gone)
            else
                connect(client, &QLocalSocket::disconnected, this, received);
        }
    });
    return true;
}
