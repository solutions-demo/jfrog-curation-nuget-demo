using FluentValidation;
using Newtonsoft.Json;

#if DEMO_LICENSE
using OfficeOpenXml;
#endif

var order = new DemoOrder("JFrog Curation demo", 2);
var validation = new DemoOrderValidator().Validate(order);
if (!validation.IsValid)
{
    Console.Error.WriteLine(string.Join("; ", validation.Errors.Select(error => error.ErrorMessage)));
    return 1;
}

var result = new Dictionary<string, object>
{
    ["customer"] = order.Customer,
    ["quantity"] = order.Quantity,
    ["valid"] = validation.IsValid
};

#if DEMO_LICENSE
// Refer to the package API without generating a workbook under an unverified license.
result["spreadsheet_library"] = typeof(ExcelPackage).Assembly.GetName().Name ?? "EPPlus";
#endif

Console.WriteLine(JsonConvert.SerializeObject(result));
return 0;

internal sealed record DemoOrder(string Customer, int Quantity);

internal sealed class DemoOrderValidator : AbstractValidator<DemoOrder>
{
    public DemoOrderValidator()
    {
        RuleFor(order => order.Customer).NotEmpty();
        RuleFor(order => order.Quantity).GreaterThan(0);
    }
}
