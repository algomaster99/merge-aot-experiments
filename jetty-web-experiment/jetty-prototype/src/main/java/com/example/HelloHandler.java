package com.example;

import org.eclipse.jetty.http.HttpHeader;
import org.eclipse.jetty.server.Handler;
import org.eclipse.jetty.server.Request;
import org.eclipse.jetty.server.Response;
import org.eclipse.jetty.util.Callback;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;

public class HelloHandler extends Handler.Abstract {

    @Override
    public boolean handle(Request request, Response response, Callback callback) throws Exception {
        long start = System.nanoTime();
        try {
            byte[] body = "Hello, World!\n".getBytes(StandardCharsets.UTF_8);
            response.setStatus(200);
            response.getHeaders().put(HttpHeader.CONTENT_TYPE, "text/plain; charset=utf-8");
            response.write(true, ByteBuffer.wrap(body), callback);
            return true;
        } finally {
            System.out.printf("[/hello] %.3f ms%n", (System.nanoTime() - start) / 1_000_000.0);
        }
    }
}
