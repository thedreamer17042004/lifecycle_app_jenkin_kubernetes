using System.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using crud_asp.net_core.Models;
using crud_asp.net_core.Data;
using Microsoft.EntityFrameworkCore;
using crud_asp.net_core.Models.ViewModels;
using Microsoft.AspNetCore.Mvc.Rendering;

namespace crud_asp.net_core.Controllers;

public class HomeController : Controller
{
    private readonly AppDbContext _dbContext;

    public HomeController(AppDbContext context)
    {
        _dbContext = context;
    }

    public IActionResult Index()
    {
        List<Empleado> list = _dbContext.Empleados.Include(c => c.oCargo).ToList();
        return View(list);
    }

    [HttpGet]
    public IActionResult Empleado_Detalle(int IdEmpleado)
    {
        EmpleadoVM oEmpleadoVM = new EmpleadoVM()
        {
            oEmpleado = new Empleado(),

            oListCargo = _dbContext.Cargos.Select(cargo => new SelectListItem()
            {
                Text = cargo.Description,
                Value = cargo.IdCargo.ToString()

            }).ToList()
        };

        if (IdEmpleado != 0)
        {
            oEmpleadoVM.oEmpleado = _dbContext.Empleados.Find(IdEmpleado);
        }

        return View(oEmpleadoVM);
    }

    [HttpPost]
    public IActionResult Empleado_Detalle(EmpleadoVM oEmpleadoVM)
    {
        if (oEmpleadoVM.oEmpleado.IdEmpleado == 0)
        {
            _dbContext.Empleados.Add(oEmpleadoVM.oEmpleado);

        }
        else
        {
            _dbContext.Empleados.Update(oEmpleadoVM.oEmpleado);
        }

        _dbContext.SaveChanges();

        return RedirectToAction("Index", "Home");
    }



    [HttpGet]
    public IActionResult Eliminar(int IdEmpleado)
    {
        Empleado oEmpleado = _dbContext.Empleados.Include(c => c.oCargo).Where(e => e.IdEmpleado == IdEmpleado).FirstOrDefault();

        return View(oEmpleado);
    }

    [HttpPost]
    public IActionResult Eliminar(Empleado oEmpleado)
    {
        _dbContext.Empleados.Remove(oEmpleado);
        _dbContext.SaveChanges();

        return RedirectToAction("Index", "Home");
    }

}
