package com.example;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.eclipse.jetty.http.HttpHeader;
import org.eclipse.jetty.server.Handler;
import org.eclipse.jetty.server.Request;
import org.eclipse.jetty.server.Response;
import org.eclipse.jetty.util.Callback;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;

public class JsonHandler extends Handler.Abstract {

    // ObjectMapper is expensive to construct — kept as field to mimic real app usage.
    // First request will still trigger Jackson's internal class loading.
    private final ObjectMapper mapper = new ObjectMapper();

    @Override
    public boolean handle(Request request, Response response, Callback callback) throws Exception {
        long start = System.nanoTime();
        try {
            ObjectNode root = mapper.createObjectNode();
            root.put("message", "Hello from /json");
            root.put("timestamp", System.currentTimeMillis());

            ArrayNode items = root.putArray("items");
            items.add("alpha");
            items.add("beta");
            items.add("gamma");

            ObjectNode meta = root.putObject("metadata");
            meta.put("version", "1.0");
            meta.put("server", "jetty");
            meta.put("endpoint", "/json");

            byte[] body = mapper.writeValueAsBytes(root);
            response.setStatus(200);
            response.getHeaders().put(HttpHeader.CONTENT_TYPE, "application/json; charset=utf-8");
            response.write(true, ByteBuffer.wrap(body), callback);
            return true;
        } finally {
            System.out.printf("[/json]  %.3f ms%n", (System.nanoTime() - start) / 1_000_000.0);
        }
    }
}
