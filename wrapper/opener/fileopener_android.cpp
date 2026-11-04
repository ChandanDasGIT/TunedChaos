// Android: what Android asks the app to open comes through OpenedFiles.java
// (file paths by then), now and whenever it asks again.
#include "wrapper/opener/fileopener.h"

#include <QCoreApplication>
#include <QJniEnvironment>
#include <QJniObject>
#include <QPointer>

namespace {

constexpr char kOpenedFiles[] = "io/github/chandandasgit/tunedchaos/OpenedFiles";
QPointer<FileOpener> s_opener;

void takePending()
{
    const QJniObject list = QJniObject::callStaticObjectMethod(kOpenedFiles, "takePending", "()[Ljava/lang/String;");
    if (!list.isValid())
        return;
    QJniEnvironment env;
    const auto array = list.object<jobjectArray>();
    QStringList files;
    for (jsize i = 0, n = env->GetArrayLength(array); i < n; ++i) {
        const QJniObject item(env->GetObjectArrayElement(array, i));
        files << item.toString();
    }
    if (!files.isEmpty() && s_opener)
        s_opener->open(files);
}

// Android's thread: more to open
void nativeFilesOpened(JNIEnv *, jclass)
{
    QMetaObject::invokeMethod(QCoreApplication::instance(), [] { takePending(); }, Qt::QueuedConnection);
}

} // namespace

void FileOpener::listenToSystem()
{
    s_opener = this;
    static const JNINativeMethod methods[] = {
        {"nativeFilesOpened", "()V", reinterpret_cast<void *>(nativeFilesOpened)}};
    QJniEnvironment env;
    env.registerNativeMethods(kOpenedFiles, methods, 1);
    takePending(); // (what opened the app, if anything)
}
