package com.example;

import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.pdmodel.PDPageContentStream;
import org.apache.pdfbox.pdmodel.common.PDRectangle;
import org.apache.pdfbox.pdmodel.font.PDType1Font;
import org.apache.pdfbox.pdmodel.font.Standard14Fonts;
import org.eclipse.jetty.http.HttpHeader;
import org.eclipse.jetty.server.Handler;
import org.eclipse.jetty.server.Request;
import org.eclipse.jetty.server.Response;
import org.eclipse.jetty.util.Callback;

import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;

public class PdfHandler extends Handler.Abstract {

    @Override
    public boolean handle(Request request, Response response, Callback callback) throws Exception {
        long start = System.nanoTime();
        try {
            byte[] pdfBytes = generatePdf();
            response.setStatus(200);
            response.getHeaders().put(HttpHeader.CONTENT_TYPE, "application/pdf");
            response.write(true, ByteBuffer.wrap(pdfBytes), callback);
            return true;
        } finally {
            System.out.printf("[/pdf]   %.3f ms%n", (System.nanoTime() - start) / 1_000_000.0);
        }
    }

    private byte[] generatePdf() throws Exception {
        try (PDDocument doc = new PDDocument()) {
            PDPage page = new PDPage(PDRectangle.A4);
            doc.addPage(page);

            PDType1Font font = new PDType1Font(Standard14Fonts.FontName.HELVETICA_BOLD);
            PDType1Font bodyFont = new PDType1Font(Standard14Fonts.FontName.HELVETICA);

            try (PDPageContentStream cs = new PDPageContentStream(doc, page)) {
                cs.beginText();
                cs.setFont(font, 18);
                cs.newLineAtOffset(60, 760);
                cs.showText("AOT Cache Benchmark Report");
                cs.endText();

                cs.beginText();
                cs.setFont(bodyFont, 12);
                cs.newLineAtOffset(60, 720);
                cs.setLeading(18.0f);
                cs.showText("Endpoint: /pdf");
                cs.newLine();
                cs.showText("Generated at: " + java.time.Instant.now());
                cs.newLine();
                cs.showText("This document exercises PDFBox font and rendering classes.");
                cs.endText();
            }

            ByteArrayOutputStream baos = new ByteArrayOutputStream();
            doc.save(baos);
            return baos.toByteArray();
        }
    }
}
