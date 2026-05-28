package dev.fopexp;

import org.apache.fop.apps.Fop;
import org.apache.fop.apps.FopFactory;
import org.apache.fop.apps.FOUserAgent;
import org.apache.fop.apps.MimeConstants;

import javax.xml.transform.Transformer;
import javax.xml.transform.TransformerFactory;
import javax.xml.transform.Source;
import javax.xml.transform.Result;
import javax.xml.transform.stream.StreamSource;
import javax.xml.transform.sax.SAXResult;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

/**
 * Apache FOP startup benchmark.
 *
 * Each workload renders the same XSL-FO document to a different output format.
 * The FO parsing / layout front-end (fop-core layout engine, batik for any
 * embedded SVG, fontbox for font handling) is shared, while each output format
 * loads a completely independent renderer / document-handler class subtree:
 *
 *   fo-to-pdf  -> org.apache.fop.render.pdf.*  + the PDF library
 *   fo-to-ps   -> org.apache.fop.render.ps.*   (PostScript)
 *   fo-to-pcl  -> org.apache.fop.render.pcl.*  (HP PCL)
 *   fo-to-rtf  -> org.apache.fop.render.rtf.*  (rtflib)
 *   fo-to-txt  -> org.apache.fop.render.txt.*  (plain text)
 *   fo-to-png  -> org.apache.fop.render.bitmap.* + Java2D / ImageIO raster
 */
public class Main {

    public static void main(String[] args) throws Exception {
        System.setProperty("java.awt.headless", "true");
        if (args.length < 2) {
            System.err.println("Usage: Main <command> <workdir>");
            System.exit(1);
        }
        String cmd = args[0];
        Path workDir = Paths.get(args[1]);
        switch (cmd) {
            case "prepare"  -> prepare(workDir);
            case "fo-to-pdf" -> render(workDir, MimeConstants.MIME_PDF);
            case "fo-to-ps"  -> render(workDir, MimeConstants.MIME_POSTSCRIPT);
            case "fo-to-pcl" -> render(workDir, MimeConstants.MIME_PCL);
            case "fo-to-rtf" -> render(workDir, MimeConstants.MIME_RTF);
            case "fo-to-txt" -> render(workDir, MimeConstants.MIME_PLAIN_TEXT);
            case "fo-to-png" -> render(workDir, MimeConstants.MIME_PNG);
            default -> { System.err.println("Unknown command: " + cmd); System.exit(1); }
        }
    }

    static void prepare(Path workDir) throws Exception {
        Files.createDirectories(workDir);
        Files.writeString(workDir.resolve("sample.fo"), SAMPLE_FO);
    }

    static void render(Path workDir, String mime) throws Exception {
        File fo = workDir.resolve("sample.fo").toFile();
        FopFactory fopFactory = FopFactory.newInstance(workDir.toUri());
        FOUserAgent ua = fopFactory.newFOUserAgent();
        try (OutputStream out = new ByteArrayOutputStream()) {
            Fop fop = fopFactory.newFop(mime, ua, out);
            Transformer transformer = TransformerFactory.newInstance().newTransformer();
            Source src = new StreamSource(fo);
            Result res = new SAXResult(fop.getDefaultHandler());
            transformer.transform(src, res);
        }
    }

    // A small but non-trivial FO document: a page sequence with a block-level
    // table, inline styling, a list and a leader. Exercises the common layout
    // managers that every renderer must consume.
    static final String SAMPLE_FO = """
        <?xml version="1.0" encoding="UTF-8"?>
        <fo:root xmlns:fo="http://www.w3.org/1999/XSL/Format">
          <fo:layout-master-set>
            <fo:simple-page-master master-name="A4"
                page-height="29.7cm" page-width="21cm"
                margin="2cm">
              <fo:region-body/>
            </fo:simple-page-master>
          </fo:layout-master-set>
          <fo:page-sequence master-reference="A4">
            <fo:flow flow-name="xsl-region-body">
              <fo:block font-size="18pt" font-weight="bold"
                  space-after="6pt">AOT Cache Benchmark</fo:block>
              <fo:block space-after="6pt">
                This document exercises the <fo:inline font-style="italic">FOP</fo:inline>
                layout engine and one output renderer.
              </fo:block>
              <fo:block space-after="6pt">
                Leader: start<fo:leader leader-pattern="dots"/>end
              </fo:block>
              <fo:list-block provisional-distance-between-starts="12mm">
                <fo:list-item>
                  <fo:list-item-label end-indent="label-end()">
                    <fo:block>1.</fo:block>
                  </fo:list-item-label>
                  <fo:list-item-body start-indent="body-start()">
                    <fo:block>First item</fo:block>
                  </fo:list-item-body>
                </fo:list-item>
                <fo:list-item>
                  <fo:list-item-label end-indent="label-end()">
                    <fo:block>2.</fo:block>
                  </fo:list-item-label>
                  <fo:list-item-body start-indent="body-start()">
                    <fo:block>Second item</fo:block>
                  </fo:list-item-body>
                </fo:list-item>
              </fo:list-block>
              <fo:table table-layout="fixed" width="100%" space-before="6pt"
                  border="0.5pt solid black">
                <fo:table-column column-width="50%"/>
                <fo:table-column column-width="50%"/>
                <fo:table-body>
                  <fo:table-row>
                    <fo:table-cell border="0.5pt solid black" padding="2pt">
                      <fo:block font-weight="bold">Key</fo:block>
                    </fo:table-cell>
                    <fo:table-cell border="0.5pt solid black" padding="2pt">
                      <fo:block font-weight="bold">Value</fo:block>
                    </fo:table-cell>
                  </fo:table-row>
                  <fo:table-row>
                    <fo:table-cell border="0.5pt solid black" padding="2pt">
                      <fo:block>startup</fo:block>
                    </fo:table-cell>
                    <fo:table-cell border="0.5pt solid black" padding="2pt">
                      <fo:block>fast</fo:block>
                    </fo:table-cell>
                  </fo:table-row>
                </fo:table-body>
              </fo:table>
            </fo:flow>
          </fo:page-sequence>
        </fo:root>
        """;
}
