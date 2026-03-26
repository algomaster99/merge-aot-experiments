package com.example;

import org.eclipse.jetty.server.Server;
import org.eclipse.jetty.server.handler.PathMappingsHandler;
import org.eclipse.jetty.http.pathmap.ServletPathSpec;

public class Main {
    public static void main(String[] args) throws Exception {
        Server server = new Server(8080);

        PathMappingsHandler paths = new PathMappingsHandler();
        paths.addMapping(new ServletPathSpec("/hello"), new HelloHandler());
        paths.addMapping(new ServletPathSpec("/json"), new JsonHandler());
        paths.addMapping(new ServletPathSpec("/pdf"), new PdfHandler());

        server.setHandler(paths);
        server.start();
        System.out.println("Server started on http://localhost:8080");
        System.out.println("Endpoints: /hello  /json  /pdf");
        server.join();
    }
}
