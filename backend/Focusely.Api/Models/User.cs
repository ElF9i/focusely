namespace Focusely.Api.Models;

public class User
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string FirstName { get; set; } = "";
    public string LastName { get; set; } = "";
    public string Username { get; set; } = "";
    public string Email { get; set; } = "";
    public string PasswordHash { get; set; } = "";
    public string? Country { get; set; }
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}
