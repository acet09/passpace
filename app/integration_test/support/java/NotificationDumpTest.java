package com.passpace.tools;

import com.android.uiautomator.core.Configurator;
import com.android.uiautomator.testrunner.UiAutomatorTestCase;

/** Reads a live chronometer without waiting for its one-second updates to idle. */
public final class NotificationDumpTest extends UiAutomatorTestCase {
    public void testSnapshot() throws Exception {
        Configurator.getInstance().setWaitForIdleTimeout(0);
        String output = getParams().getString("out", "passpace-notification-live.xml");
        if (!output.matches("passpace-[a-z0-9-]+\\.xml")) throw new IllegalArgumentException("Invalid test output");
        getUiDevice().dumpWindowHierarchy(output);
    }
}
