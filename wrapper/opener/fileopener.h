#pragma once

#include <QObject>
#include <QStringList>
#include <QThreadPool>

class LibraryController;
class PlaylistController;

// Music files the system asks the app to open (double-click, "Open with",
// Android's "open with" / share): they go to the end of the Queue and the
// first one plays. M3U playlists open as their songs; folders are scanned
// like a dropped folder. On Android it also takes what Android hands over
// (fileopener_android.cpp).
class FileOpener : public QObject
{
    Q_OBJECT

public:
    FileOpener(PlaylistController *playlist, LibraryController *library, QObject *parent);
    ~FileOpener() override;

    // Paths or file:// URLs
    void open(const QStringList &files);
    // The files among a command line (what follows the program; options left out)
    static QStringList filesIn(const QStringList &arguments);

    // Android: takes the files Android asked to open, now and whenever it asks again.
    void listenToSystem();

signals:
    void opened(); // (the window comes to the front)

private:
    PlaylistController *m_playlist;
    LibraryController *m_library;
    QThreadPool m_pool;
};
