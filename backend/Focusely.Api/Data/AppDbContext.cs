using Focusely.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace Focusely.Api.Data;

public class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<StudySession> StudySessions => Set<StudySession>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<User>().HasIndex(u => u.Email).IsUnique();
        b.Entity<User>().HasIndex(u => u.Username).IsUnique();
        b.Entity<StudySession>().HasIndex(s => new { s.UserId, s.StartedAtUtc });
        b.Entity<StudySession>().Property(s => s.Mode).HasConversion<string>();
    }
}
