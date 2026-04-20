package dev.compressexp;

import org.apache.commons.compress.archivers.ArchiveEntry;
import org.apache.commons.compress.archivers.ArchiveInputStream;
import org.apache.commons.compress.archivers.ArchiveOutputStream;
import org.apache.commons.compress.archivers.tar.TarArchiveEntry;
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream;
import org.apache.commons.compress.archivers.tar.TarArchiveOutputStream;
import org.apache.commons.compress.archivers.zip.ZipArchiveEntry;
import org.apache.commons.compress.archivers.zip.ZipArchiveInputStream;
import org.apache.commons.compress.archivers.zip.ZipArchiveOutputStream;
import org.apache.commons.compress.compressors.gzip.GzipCompressorInputStream;
import org.apache.commons.compress.compressors.gzip.GzipCompressorOutputStream;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;

public class Main {

    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.err.println("Usage: Main <command> <workdir>");
            System.exit(1);
        }
        String cmd = args[0];
        Path workDir = Paths.get(args[1]);
        switch (cmd) {
            case "prepare"       -> prepare(workDir);
            case "zip-roundtrip" -> zipRoundtrip(workDir);
            case "tar-roundtrip" -> tarRoundtrip(workDir);
            case "gzip-roundtrip"-> gzipRoundtrip(workDir);
            case "list-archives" -> listArchives(workDir);
            default -> { System.err.println("Unknown command: " + cmd); System.exit(1); }
        }
    }

    static final String[] FILE_NAMES = {"alpha.txt", "beta.txt", "gamma.txt"};

    static void prepare(Path workDir) throws IOException {
        Files.createDirectories(workDir);
        for (String name : FILE_NAMES) {
            Files.writeString(workDir.resolve(name),
                "content of " + name + "\n".repeat(100),
                StandardCharsets.UTF_8);
        }
        // pre-create archives so list-archives has something to read
        zipRoundtrip(workDir);
        tarRoundtrip(workDir);
        gzipRoundtrip(workDir);
    }

    static void zipRoundtrip(Path workDir) throws IOException {
        Path zip = workDir.resolve("archive.zip");
        try (ZipArchiveOutputStream out = new ZipArchiveOutputStream(zip.toFile())) {
            for (String name : FILE_NAMES) {
                byte[] data = Files.readAllBytes(workDir.resolve(name));
                ZipArchiveEntry entry = new ZipArchiveEntry(name);
                entry.setSize(data.length);
                out.putArchiveEntry(entry);
                out.write(data);
                out.closeArchiveEntry();
            }
        }
        try (ZipArchiveInputStream in = new ZipArchiveInputStream(
                new BufferedInputStream(new FileInputStream(zip.toFile())))) {
            ZipArchiveEntry entry;
            while ((entry = (ZipArchiveEntry) in.getNextEntry()) != null) {
                in.readAllBytes();
            }
        }
    }

    static void tarRoundtrip(Path workDir) throws IOException {
        Path tar = workDir.resolve("archive.tar");
        try (TarArchiveOutputStream out = new TarArchiveOutputStream(
                new BufferedOutputStream(new FileOutputStream(tar.toFile())))) {
            for (String name : FILE_NAMES) {
                byte[] data = Files.readAllBytes(workDir.resolve(name));
                TarArchiveEntry entry = new TarArchiveEntry(name);
                entry.setSize(data.length);
                out.putArchiveEntry(entry);
                out.write(data);
                out.closeArchiveEntry();
            }
        }
        try (TarArchiveInputStream in = new TarArchiveInputStream(
                new BufferedInputStream(new FileInputStream(tar.toFile())))) {
            TarArchiveEntry entry;
            while ((entry = (TarArchiveEntry) in.getNextEntry()) != null) {
                in.readAllBytes();
            }
        }
    }

    static void gzipRoundtrip(Path workDir) throws IOException {
        Path src = workDir.resolve("alpha.txt");
        Path gz  = workDir.resolve("alpha.txt.gz");
        try (GzipCompressorOutputStream out = new GzipCompressorOutputStream(
                new BufferedOutputStream(new FileOutputStream(gz.toFile())))) {
            out.write(Files.readAllBytes(src));
        }
        try (GzipCompressorInputStream in = new GzipCompressorInputStream(
                new BufferedInputStream(new FileInputStream(gz.toFile())))) {
            in.readAllBytes();
        }
    }

    static void listArchives(Path workDir) throws IOException {
        for (String archive : new String[]{"archive.zip", "archive.tar"}) {
            Path p = workDir.resolve(archive);
            if (!Files.exists(p)) continue;
            if (archive.endsWith(".zip")) {
                try (ZipArchiveInputStream in = new ZipArchiveInputStream(
                        new BufferedInputStream(new FileInputStream(p.toFile())))) {
                    while (in.getNextEntry() != null) {}
                }
            } else {
                try (TarArchiveInputStream in = new TarArchiveInputStream(
                        new BufferedInputStream(new FileInputStream(p.toFile())))) {
                    while (in.getNextEntry() != null) {}
                }
            }
        }
    }
}
