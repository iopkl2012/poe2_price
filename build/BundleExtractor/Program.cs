using LibBundle3;
using LibBundle3.Records;
using System.Text;

class Program
{
    static int Main(string[] args)
    {
        if (args.Length < 3)
        {
            Console.WriteLine("Usage: BundleExtractor <index.bin> <file_path> <output_path>");
            Console.WriteLine("  index.bin    : Path to _.index.bin");
            Console.WriteLine("  file_path    : File path in bundle (e.g. data/balance/baseitemtypes.datc64)");
            Console.WriteLine("  output_path  : Output file path");
            return 1;
        }

        string indexPath = args[0];
        string filePath = args[1];
        string outputPath = args[2];

        try
        {
            if (!File.Exists(indexPath))
            {
                Console.WriteLine($"Error: Index file not found: {indexPath}");
                return 1;
            }

            // 获取 Bundles2 目录
            string bundles2Dir = Path.GetDirectoryName(indexPath) ?? "";
            if (string.IsNullOrEmpty(bundles2Dir))
            {
                bundles2Dir = Environment.CurrentDirectory;
            }

            Console.WriteLine($"Loading index: {indexPath}");
            Console.WriteLine($"Bundles2 dir: {bundles2Dir}");

            // 创建 Index (不自动解析路径，避免解析失败时抛出异常)
            var factory = new DriveBundleFactory(bundles2Dir);
            using var index = new LibBundle3.Index(indexPath, false, factory);
            
            // 手动解析路径，忽略失败的文件
            int failedPaths = index.ParsePaths();
            if (failedPaths > 0)
            {
                Console.WriteLine($"Warning: {failedPaths} files failed to parse paths (ignored)");
            }

            Console.WriteLine($"Index loaded. Files count: {index.Files.Count}");

            // 查找文件
            FileRecord? targetFile = null;
            foreach (var file in index.Files.Values)
            {
                if (file.Path?.Equals(filePath, StringComparison.OrdinalIgnoreCase) == true)
                {
                    targetFile = file;
                    break;
                }
            }

            if (targetFile == null)
            {
                // 尝试模糊匹配
                foreach (var file in index.Files.Values)
                {
                    if (file.Path?.Contains(filePath, StringComparison.OrdinalIgnoreCase) == true)
                    {
                        Console.WriteLine($"Found similar file: {file.Path}");
                        targetFile = file;
                        break;
                    }
                }
            }

            if (targetFile == null)
            {
                Console.WriteLine($"Error: File not found in bundle: {filePath}");
                return 1;
            }

            Console.WriteLine($"Found file: {targetFile.Path}");
            Console.WriteLine($"  Size: {targetFile.Size} bytes");
            Console.WriteLine($"  Offset: {targetFile.Offset}");
            Console.WriteLine($"  Bundle: {targetFile.BundleRecord.Path}");

            // 读取文件内容
            Console.WriteLine("Reading file content...");
            byte[] data;
            using (var bundle = factory.GetBundle(targetFile.BundleRecord))
            {
                data = targetFile.Read(bundle).ToArray();
            }

            // 保存到输出路径
            string outputDir = Path.GetDirectoryName(outputPath) ?? "";
            if (!string.IsNullOrEmpty(outputDir))
            {
                Directory.CreateDirectory(outputDir);
            }

            File.WriteAllBytes(outputPath, data);
            Console.WriteLine($"Successfully extracted to: {outputPath} ({data.Length} bytes)");

            return 0;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error: {ex.GetType().Name}: {ex.Message}");
            Console.WriteLine(ex.StackTrace);
            return 1;
        }
    }
}
