namespace Focusely.Api.Models;

public enum SessionMode { Focus, Pomodoro, Stopwatch }

public class StudySession
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public User? User { get; set; }
    public SessionMode Mode { get; set; }
    public DateTime StartedAtUtc { get; set; }
    public DateTime? PausedAtUtc { get; set; }
    public int PausedSeconds { get; set; }
    public DateTime? EndedAtUtc { get; set; }
    public int? TargetSeconds { get; set; }
    public int StudySeconds { get; set; }
    public bool IsValidated { get; set; }
}
