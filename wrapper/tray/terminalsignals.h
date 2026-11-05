#pragma once

#include <QObject>

class QSocketNotifier;

// Linux: the signals a terminal or the session sends, turned into Qt signals
// (a signal handler may do almost nothing itself, so it writes a byte to a
// socket that the event loop reads).
//  Ctrl+C in the terminal (SIGINT): interrupted(), the app goes to the tray.
//  Logout, shutdown, `kill` (SIGTERM), the terminal closed (SIGHUP): terminated(),
//  the app quits properly (saving what it should).
class TerminalSignals : public QObject
{
    Q_OBJECT

public:
    explicit TerminalSignals(QObject *parent);
    ~TerminalSignals() override;

signals:
    void interrupted();
    void terminated();

private:
    QSocketNotifier *m_notifier = nullptr;
};
