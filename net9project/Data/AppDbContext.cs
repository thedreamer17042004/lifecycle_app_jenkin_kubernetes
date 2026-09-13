using Microsoft.EntityFrameworkCore;

namespace crud_asp.net_core.Data
{
    public partial class AppDbContext(IConfiguration configuration) : DbContext
    {
        protected readonly IConfiguration Configuration = configuration;

        protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder)
        {
            optionsBuilder.UseNpgsql(Configuration.GetConnectionString("WebApiDatabase"));
        }

        public virtual required DbSet<Cargo> Cargos { get; set; }
        public virtual required DbSet<Empleado> Empleados { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<Cargo>(entity =>
            {
                entity.HasKey(e => e.IdCargo).HasName("PK__CARGO__6C985625FAABC3E6");

                entity.ToTable("Cargos");

                entity.Property(e => e.Description).HasMaxLength(50).IsRequired();
            });

            modelBuilder.Entity<Empleado>(entity =>
            {
                entity.HasKey(e => e.IdEmpleado).HasName("PK__EMPLEADO__CE6D8B9E7F9FE85C");

                entity.ToTable("Empleados");

                entity.Property(e => e.NombreCompleto).HasMaxLength(100).IsRequired().IsUnicode(false); ;

                entity.Property(e => e.Telefono).HasMaxLength(25).IsRequired().IsUnicode(false);

                entity.Property(e => e.Email).HasMaxLength(100).IsRequired();

                entity.HasOne(d => d.oCargo)
                    .WithMany(p => p.Empleados)
                    .HasForeignKey(d => d.CargoId)
                    .HasConstraintName("FK_Cargo");
            });

            OnModelCreatingPartial(modelBuilder);
        }

        partial void OnModelCreatingPartial(ModelBuilder modelBuilder);
    }
}