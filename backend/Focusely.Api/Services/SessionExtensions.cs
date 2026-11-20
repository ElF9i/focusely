using Focusely.Api.Dtos;
using Focusely.Api.Models;

namespace Focusely.Api.Services;

public static class SessionExtensions
{
    public const int MinValidSeconds = 60;   // RG01 : duree minimale validee

    // Temps d'etude = (fin ou pause en cours ou maintenant) - debut - pauses terminees
    public static int ComputeStudySeconds(this StudySession s, DateTime nowUtc)
    {
        var end = s.EndedAtUtc ?? s.PausedAtUtc ?? nowUtc;
        var total = (int)(end - s.StartedAtUtc).TotalSeconds;
        return Math.Max(0, total - s.PausedSeconds);
    }

    public static SessionDto ToDto(this StudySession s)
    {
        var now = DateTime.UtcNow;
        return new SessionDto(s.Id, s.Mode.ToString(), s.StartedAtUtc, s.PausedAtUtc,
            s.PausedSeconds, s.EndedAtUtc, s.TargetSeconds,
            s.EndedAtUtc != null ? s.StudySeconds : s.ComputeStudySeconds(now),
            s.IsValidated, now, s.SubjectId);
    }
}
