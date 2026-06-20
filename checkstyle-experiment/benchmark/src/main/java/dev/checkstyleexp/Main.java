package dev.checkstyleexp;

import com.puppycrawl.tools.checkstyle.Checker;
import com.puppycrawl.tools.checkstyle.ConfigurationLoader;
import com.puppycrawl.tools.checkstyle.PropertiesExpander;
import com.puppycrawl.tools.checkstyle.api.Configuration;

import java.io.File;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Properties;
import java.util.stream.Collectors;

public class Main {

    public static void main(String[] args) throws Exception {
        if (args.length < 3) {
            System.err.println("Usage: Main <workload> <configs-dir> <sources-dir>");
            System.exit(1);
        }
        String workload = args[0];
        String configsDir = args[1];
        String sourcesDir = args[2];

        String configFile = configsDir + "/" + workload + ".xml";

        Properties props = new Properties();
        props.setProperty("basedir", new File(sourcesDir).getAbsolutePath());

        Configuration config = ConfigurationLoader.loadConfiguration(
            configFile, new PropertiesExpander(props));

        Checker checker = new Checker();
        checker.setModuleClassLoader(Main.class.getClassLoader());
        checker.configure(config);

        List<File> files = Files.walk(Path.of(sourcesDir))
            .filter(p -> p.toString().endsWith(".java"))
            .map(Path::toFile)
            .collect(Collectors.toList());

        checker.process(files);
        checker.destroy();
    }
}
