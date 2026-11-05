#include "terminalsignals.h"

#include <QSocketNotifier>

#include <csignal>
#include <sys/socket.h>
#include <unistd.h>

namespace {

int g_sockets[2] = {-1, -1}; // [0] written by the handler, [1] read by the event loop

void onSignal(int number)
{
    const char byte = static_cast<char>(number);
    [[maybe_unused]] const ssize_t written = ::write(g_sockets[0], &byte, 1);
}

} // namespace

TerminalSignals::TerminalSignals(QObject *parent)
    : QObject(parent)
{
    if (::socketpair(AF_UNIX, SOCK_STREAM, 0, g_sockets) != 0)
        return;
    m_notifier = new QSocketNotifier(g_sockets[1], QSocketNotifier::Read, this);
    connect(m_notifier, &QSocketNotifier::activated, this, [this] {
        char byte = 0;
        if (::read(g_sockets[1], &byte, 1) != 1)
            return;
        if (byte == SIGINT)
            emit interrupted();
        else
            emit terminated();
    });

    struct sigaction action = {};
    action.sa_handler = onSignal;
    sigemptyset(&action.sa_mask);
    action.sa_flags = SA_RESTART;
    for (int number : {SIGINT, SIGTERM, SIGHUP})
        sigaction(number, &action, nullptr);
}

TerminalSignals::~TerminalSignals()
{
    for (int number : {SIGINT, SIGTERM, SIGHUP})
        std::signal(number, SIG_DFL);
}
