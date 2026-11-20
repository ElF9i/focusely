namespace Focusely.Api.Models;

public enum ChallengeType { TimeGoal, SpeedRace }

public class StudyChallenge
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid CreatorId { get; set; }
    public string Title { get; set; } = "";
    public ChallengeType Type { get; set; }
    public int TargetSeconds { get; set; }
    public DateTime StartsAtUtc { get; set; }
    public DateTime EndsAtUtc { get; set; }
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}

public class ChallengeParticipant
{
    public Guid ChallengeId { get; set; }
    public Guid UserId { get; set; }
    public DateTime JoinedAtUtc { get; set; } = DateTime.UtcNow;
}
