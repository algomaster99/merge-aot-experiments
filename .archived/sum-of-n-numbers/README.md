I ran this command to generate the assembly code:

```shell
java -XX:+UnlockDiagnosticVMOptions  -XX:CompileOnly=Main.computeSum -XX:+PrintAssembly   Main.java 100000
```

`Main.computeSum` is the only method that I want to compile.

In this case, two subsequent runs return the exact same assembly code.
