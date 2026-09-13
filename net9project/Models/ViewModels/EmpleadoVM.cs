using crud_asp.net_core.Data;
using Microsoft.AspNetCore.Mvc.Rendering;

namespace crud_asp.net_core.Models.ViewModels;

public class EmpleadoVM
{
    public Empleado oEmpleado { get; set; }

    public List<SelectListItem> oListCargo { get; set; }

}
