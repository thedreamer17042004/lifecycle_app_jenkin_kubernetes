namespace crud_asp.net_core.Data
{
    public partial class Cargo
    {
        public Cargo()
        {
            Empleados = new HashSet<Empleado>();
        }
        public int IdCargo { get; set; }
        public string Description { get; set; }

        public virtual ICollection<Empleado> Empleados { get; set; }
    }
}