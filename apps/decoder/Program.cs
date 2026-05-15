using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Formatters.Binary;
using Newtonsoft.Json;

namespace FgDecoder
{
    class Program
    {
        static int Main(string[] args)
        {
            if (args.Length < 1)
            {
                Console.Error.WriteLine("Usage: decoder.exe <path_to_file.fg>");
                Console.Error.WriteLine("       decoder.exe <path_to_file.fg> --debug");
                return 1;
            }

            string filePath = args[0];
            bool debugMode = args.Length > 1 && args[1] == "--debug";

            if (!File.Exists(filePath))
            {
                Console.Error.WriteLine($"File not found: {filePath}");
                return 1;
            }

            try
            {
                AppDomain.CurrentDomain.AssemblyResolve += ResolveAssembly;

                object root;
                using (var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read))
                {
                    var formatter = new BinaryFormatter { Binder = new AllowAllTypesBinder() };
#pragma warning disable SYSLIB0011
                    root = formatter.Deserialize(stream);
#pragma warning restore SYSLIB0011
                }

                if (debugMode)
                {
                    // Dump toàn bộ cấu trúc để biết tên field/property thực tế
                    DumpDeep(root, "ROOT", 0, maxDepth: 4);
                    return 0;
                }

                // === Parse TeacherGrade (cấu trúc đã xác nhận qua --debug) ===
                // TeacherGrade
                //   .SubjectClassGrades → List<SubjectClassGrade>
                //       .Subject (string)  — môn học
                //       .Class   (string)  — mã lớp
                //       .Students → List<Student>
                //           .Roll, .Name, .Comment (properties)
                //           .Grades → List<GradeComponent>
                //               .Component (tên thành phần)
                //               .Grade     (điểm)

                var output = new FgOutput();
                output.TypeName = root.GetType().FullName;
                output.Version  = GetField<string>(root, "Version");
                output.Semester = GetField<string>(root, "Semester");
                output.Login    = GetField<string>(root, "Login");

                var subjectClassGrades = GetField<IEnumerable>(root, "SubjectClassGrades");
                if (subjectClassGrades != null)
                {
                    foreach (var scg in subjectClassGrades)
                    {
                        var sc = new SubjectClassResult();
                        // Đúng tên field: Subject + Class
                        sc.Subject = GetAnyStringField(scg, "Subject");
                        sc.Class   = GetAnyStringField(scg, "Class");

                        // Lấy list sinh viên từ field "Students"
                        var studentsEnum = GetField<IEnumerable>(scg, "Students");
                        if (studentsEnum != null)
                        {
                            int stt = 1;
                            foreach (var stu in studentsEnum)
                            {
                                if (stu == null) continue;

                                // Student dùng auto-property → backing field <Roll>k__BackingField
                                // Nhưng GetAnyStringField tìm property trước → đúng
                                var roll    = GetAnyStringField(stu, "Roll");
                                var name    = GetAnyStringField(stu, "Name");
                                var comment = GetAnyStringField(stu, "Comment");

                                // Lấy các GradeComponent
                                var gradeComponents = new List<GradeComponentRecord>();
                                var gradesEnum = GetField<IEnumerable>(stu, "Grades");
                                if (gradesEnum != null)
                                {
                                    foreach (var gc in gradesEnum)
                                    {
                                        if (gc == null) continue;
                                        gradeComponents.Add(new GradeComponentRecord
                                        {
                                            Component = GetAnyStringField(gc, "Component") ?? "",
                                            Grade     = GetAnyStringField(gc, "Grade")     ?? ""
                                        });
                                    }
                                }

                                sc.Students.Add(new StudentRecord
                                {
                                    Stt        = stt++,
                                    Roll       = roll    ?? "",
                                    Name       = name    ?? "",
                                    Comment    = comment ?? "",
                                    Grades     = gradeComponents
                                });
                            }
                        }

                        output.SubjectClasses.Add(sc);
                    }
                }

                var json = JsonConvert.SerializeObject(output, Formatting.None);
                Console.Write(json);
                return 0;
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"ERROR {ex.GetType().Name}: {ex.Message}");
                Console.Error.WriteLine(ex.StackTrace);
                return 1;
            }
        }

        // ──────────────────────────────────────────────
        // Trích xuất danh sách sinh viên từ một object bất kỳ
        // bằng cách duyệt tất cả fields/properties và tìm collection
        // ──────────────────────────────────────────────
        static List<StudentRecord> ExtractStudentsFromObject(object obj)
        {
            if (obj == null) return new List<StudentRecord>();
            var type = obj.GetType();

            // Duyệt fields
            foreach (var field in type.GetFields(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance))
            {
                try
                {
                    var val = field.GetValue(obj);
                    if (val is IEnumerable enumerable && !(val is string))
                    {
                        var list = TryParseStudentList(enumerable);
                        if (list.Count > 0) return list;
                    }
                }
                catch { }
            }

            // Duyệt properties
            foreach (var prop in type.GetProperties(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance))
            {
                try
                {
                    var val = prop.GetValue(obj);
                    if (val is IEnumerable enumerable && !(val is string))
                    {
                        var list = TryParseStudentList(enumerable);
                        if (list.Count > 0) return list;
                    }
                }
                catch { }
            }

            return new List<StudentRecord>();
        }

        static List<StudentRecord> TryParseStudentList(IEnumerable enumerable)
        {
            var list = new List<StudentRecord>();
            int stt = 1;

            foreach (var item in enumerable)
            {
                if (item == null) continue;

                // Thử lấy Roll
                var roll = GetAnyStringField(item, "Roll", "RollNumber", "StudentCode", "Code");
                // Thử lấy Name
                var name = GetAnyStringField(item, "Name", "FullName", "StudentName");
                // Thử lấy Comment
                var comment = GetAnyStringField(item, "Comment", "Note", "Remark");

                if (!string.IsNullOrEmpty(roll) || !string.IsNullOrEmpty(name))
                {
                    list.Add(new StudentRecord
                    {
                        Stt     = stt++,
                        Roll    = roll    ?? "",
                        Name    = name    ?? "",
                        Comment = comment ?? ""
                    });
                }
            }

            return list;
        }

        // ──────────────────────────────────────────────
        // Reflection helpers
        // ──────────────────────────────────────────────

        static T GetField<T>(object obj, string name) where T : class
        {
            if (obj == null) return null;
            var type = obj.GetType();

            var field = type.GetField(name, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
            if (field != null)
            {
                try { return field.GetValue(obj) as T; } catch { }
            }

            var prop = type.GetProperty(name, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
            if (prop != null)
            {
                try { return prop.GetValue(obj) as T; } catch { }
            }

            return null;
        }

        static string GetAnyStringField(object obj, params string[] names)
        {
            if (obj == null) return null;
            var type = obj.GetType();

            foreach (var name in names)
            {
                // Field (case-insensitive)
                var field = type.GetField(name,
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.IgnoreCase);
                if (field != null)
                {
                    try
                    {
                        var v = field.GetValue(obj);
                        if (v != null) return v.ToString();
                    }
                    catch { }
                }

                // Property (case-insensitive)
                var prop = type.GetProperty(name,
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.IgnoreCase);
                if (prop != null)
                {
                    try
                    {
                        var v = prop.GetValue(obj);
                        if (v != null) return v.ToString();
                    }
                    catch { }
                }
            }

            return null;
        }

        // ──────────────────────────────────────────────
        // Debug dump — in ra stderr để không ảnh hưởng stdout JSON
        // ──────────────────────────────────────────────
        static void DumpDeep(object obj, string label, int depth, int maxDepth = 3)
        {
            if (obj == null || depth > maxDepth) return;
            string pad = new string(' ', depth * 2);
            var type = obj.GetType();

            Console.Error.WriteLine($"{pad}▶ [{label}] : {type.FullName}");

            // Fields
            foreach (var f in type.GetFields(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance))
            {
                try
                {
                    var val = f.GetValue(obj);
                    if (val == null)
                    {
                        Console.Error.WriteLine($"{pad}  F {f.Name} = null");
                        continue;
                    }
                    if (val is string || val.GetType().IsPrimitive || val.GetType().IsEnum)
                    {
                        Console.Error.WriteLine($"{pad}  F {f.Name} = \"{val}\"");
                    }
                    else if (val is IEnumerable en)
                    {
                        int cnt = 0; foreach (var _ in en) { cnt++; if (cnt > 100) break; }
                        Console.Error.WriteLine($"{pad}  F {f.Name} = [IEnumerable, ~{cnt} items]");
                        if (cnt > 0 && depth < maxDepth)
                        {
                            foreach (var item in (IEnumerable)f.GetValue(obj))
                            {
                                DumpDeep(item, $"{f.Name}[0]", depth + 1, maxDepth);
                                break; // chỉ dump 1 item đầu
                            }
                        }
                    }
                    else
                    {
                        Console.Error.WriteLine($"{pad}  F {f.Name} = [object]");
                        if (depth < maxDepth) DumpDeep(val, f.Name, depth + 1, maxDepth);
                    }
                }
                catch (Exception ex)
                {
                    Console.Error.WriteLine($"{pad}  F {f.Name} = ERROR: {ex.Message}");
                }
            }

            // Properties
            foreach (var p in type.GetProperties(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance))
            {
                try
                {
                    var val = p.GetValue(obj);
                    if (val is string || val == null || val.GetType().IsPrimitive)
                        Console.Error.WriteLine($"{pad}  P {p.Name} = \"{val}\"");
                }
                catch { }
            }
        }

        // ──────────────────────────────────────────────
        // Assembly resolver
        // ──────────────────────────────────────────────
        static Assembly ResolveAssembly(object sender, ResolveEventArgs args)
        {
            var name   = new AssemblyName(args.Name).Name;
            var exeDir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);

            foreach (var candidate in new[]
            {
                Path.Combine(exeDir, name + ".dll"),
                Path.Combine(exeDir, "libs", name + ".dll"),
            })
            {
                if (File.Exists(candidate))
                    return Assembly.LoadFrom(candidate);
            }

            return null;
        }
    }

    // ──────────────────────────────────────────────
    // Binder: chấp nhận mọi type khi BinaryFormatter deserialize
    // ──────────────────────────────────────────────
    sealed class AllowAllTypesBinder : SerializationBinder
    {
        public override Type BindToType(string assemblyName, string typeName)
        {
            foreach (var asm in AppDomain.CurrentDomain.GetAssemblies())
            {
                var t = asm.GetType(typeName, throwOnError: false, ignoreCase: true);
                if (t != null) return t;
            }
            try
            {
                var asm = Assembly.Load(assemblyName);
                return asm.GetType(typeName, throwOnError: false, ignoreCase: true);
            }
            catch { }
            return null;
        }
    }

    // ──────────────────────────────────────────────
    // Output models — khớp với cấu trúc FuGradeLib thực tế
    // ──────────────────────────────────────────────
    class FgOutput
    {
        [JsonProperty("typeName")] public string TypeName { get; set; }
        [JsonProperty("version")]  public string Version  { get; set; }
        [JsonProperty("semester")] public string Semester { get; set; }
        [JsonProperty("login")]    public string Login    { get; set; }

        [JsonProperty("subjectClasses")]
        public List<SubjectClassResult> SubjectClasses { get; set; } = new List<SubjectClassResult>();
    }

    class SubjectClassResult
    {
        [JsonProperty("subject")] public string Subject { get; set; }  // "PRN221"
        [JsonProperty("class")]   public string Class   { get; set; }  // "NET1710"

        [JsonProperty("students")]
        public List<StudentRecord> Students { get; set; } = new List<StudentRecord>();
    }

    class StudentRecord
    {
        [JsonProperty("stt")]     public int    Stt     { get; set; }
        [JsonProperty("roll")]    public string Roll    { get; set; } = "";
        [JsonProperty("name")]    public string Name    { get; set; } = "";
        [JsonProperty("comment")] public string Comment { get; set; } = "";

        [JsonProperty("grades")]
        public List<GradeComponentRecord> Grades { get; set; } = new List<GradeComponentRecord>();
    }

    class GradeComponentRecord
    {
        [JsonProperty("component")] public string Component { get; set; } = "";
        [JsonProperty("grade")]     public string Grade     { get; set; } = "";
    }
}
