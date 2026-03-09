import org.apache.pdfbox.tools.PDFBox;
import java.nio.file.Path;
import java.nio.file.Files;
import java.io.IOException;

public class Workload {

    public static void main(String[] args) throws IOException {
        Path pdf = Path.of("UPPERCASE.pdf");
        Path tempDir = Files.createTempDirectory("pdfbox");
        String basenameWithoutExtension = pdf.getFileName().toString().replace(".pdf", "");
        PDFBox.main(new String[] { "encrypt", "-O", "123", "-U", "123", "--input", pdf.toAbsolutePath().toString(), "--output", tempDir.resolve(String.format("%s-locked.pdf", basenameWithoutExtension)).toString()});
        PDFBox.main(new String[] { "decrypt", "-password", "123", "--input", tempDir.resolve(String.format("%s-locked.pdf", basenameWithoutExtension)).toString(), "--output", tempDir.resolve(String.format("%s-unlocked.pdf", basenameWithoutExtension)).toString()});
        PDFBox.main(new String[] { "export:text", "--input", tempDir.resolve(String.format("%s-unlocked.pdf", basenameWithoutExtension)).toString(), "--output", tempDir.resolve(String.format("%s-text.txt", basenameWithoutExtension)).toString()});
        PDFBox.main(new String[] { "export:images", "--input", tempDir.resolve(String.format("%s-unlocked.pdf", basenameWithoutExtension)).toString()});
        PDFBox.main(new String[] { "render", "--input", tempDir.resolve(String.format("%s-unlocked.pdf", basenameWithoutExtension)).toString()});
        PDFBox.main(new String[] { "fromtext", "--input", tempDir.resolve(String.format("%s-text.txt", basenameWithoutExtension)).toString(), "--output", tempDir.resolve(String.format("%s-from-text.pdf", basenameWithoutExtension)).toString(), "-standardFont", "Times-Roman"});
        PDFBox.main(new String[] { "split", "--input", tempDir.resolve(String.format("%s-unlocked.pdf", basenameWithoutExtension)).toString(), "-split", "3", "-outputPrefix", tempDir.resolve(String.format("split-%s", basenameWithoutExtension)).toString()});
        PDFBox.main(new String[] { "merge", "--input", tempDir.resolve(String.format("split-%s-1.pdf", basenameWithoutExtension)).toString(), "--output", tempDir.resolve(String.format("merged-%s.pdf", basenameWithoutExtension)).toString()});
        PDFBox.main(new String[] { "decode", tempDir.resolve(String.format("%s-unlocked.pdf", basenameWithoutExtension)).toString(), tempDir.resolve(String.format("%s-decoded.pdf", basenameWithoutExtension)).toString()});
        PDFBox.main(new String[] { "overlay", "-default", pdf.toAbsolutePath().toString(), "--input", tempDir.resolve(String.format("%s-unlocked.pdf", basenameWithoutExtension)).toString(), "--output", tempDir.resolve(String.format("%s-overlay.pdf", basenameWithoutExtension)).toString()});
    }
}
