package com.example.music_streaming_app;

import androidx.core.content.FileProvider;

/**
 * Exposes the downloaded update APK to the system installer.
 *
 * A subclass rather than androidx's own FileProvider: plugins (sharing, file
 * picking) declare that class too, and two {@code <provider>} entries with the
 * same name do not survive manifest merging.
 */
public class UpdateFileProvider extends FileProvider {
}
