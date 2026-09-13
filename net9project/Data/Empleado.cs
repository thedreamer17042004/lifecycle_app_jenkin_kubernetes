namespace crud_asp.net_core.Data
{
    public partial class Empleado
    {
        public int IdEmpleado { get; set; }
        public string NombreCompleto { get; set; }
        public string Telefono { get; set; }
        public string Email { get; set; }
        public int CargoId { get; set; }
        public virtual Cargo oCargo { get; set; }
    }
}