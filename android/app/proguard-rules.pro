# Keep WorkManager worker classes so R8 doesn't remove them in release builds.
-keep class * extends androidx.work.Worker
-keep class * extends androidx.work.ListenableWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}

# Keep our SMS classes explicitly.
-keep class com.matrimpathak.ledger.SmsReceiver { *; }
-keep class com.matrimpathak.ledger.SmsProcessingWorker { *; }
