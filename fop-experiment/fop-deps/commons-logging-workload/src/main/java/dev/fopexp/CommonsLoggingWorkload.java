package dev.fopexp;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.apache.commons.logging.impl.SimpleLog;

public class CommonsLoggingWorkload {

    public static void main(String[] args) {
        // Default factory lookup — exercises LogFactory discovery path
        Log log = LogFactory.getLog(CommonsLoggingWorkload.class);

        log.trace("trace message");
        log.debug("debug message");
        log.info("info message");
        log.warn("warn message");
        log.error("error message");
        log.fatal("fatal message");

        // Exercise is-enabled guards
        boolean t = log.isTraceEnabled();
        boolean d = log.isDebugEnabled();
        boolean i = log.isInfoEnabled();
        boolean w = log.isWarnEnabled();
        boolean e = log.isErrorEnabled();
        boolean f = log.isFatalEnabled();

        // Log with Throwable overload
        Throwable ex = new RuntimeException("synthetic");
        log.warn("warn with cause", ex);
        log.error("error with cause", ex);

        // Named logger (different name → new Log instance from factory)
        Log named = LogFactory.getLog("dev.fopexp.named");
        named.info("named logger");

        // SimpleLog directly — exercises the built-in implementation
        SimpleLog simple = new SimpleLog("dev.fopexp.simple");
        simple.setLevel(SimpleLog.LOG_LEVEL_ALL);
        simple.trace("simple trace");
        simple.debug("simple debug");
        simple.info("simple info");
        simple.warn("simple warn");
        simple.error("simple error");
        simple.fatal("simple fatal");

        // Release resources via factory
        LogFactory.release(Thread.currentThread().getContextClassLoader());
    }
}
