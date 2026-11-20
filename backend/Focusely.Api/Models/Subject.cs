namespace Focusely.Api.Models;

public class Subject
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string Name { get; set; } = "";
    public string Color { get; set; } = "#8B7CFF";
    public string Emoji { get; set; } = "\U0001F4D8";
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}
