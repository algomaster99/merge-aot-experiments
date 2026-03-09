public class Main {
  public static int computeSum(int n) {
    int sum = 0;
    for (int i = 1; i <= n; i++) {
      sum += i;
    }
    return sum;
  }
  public static void main(String[] args) {
    System.out.println(computeSum(Integer.parseInt(args[0])));
  }
}
