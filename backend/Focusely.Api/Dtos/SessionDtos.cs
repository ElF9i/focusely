using Focusely.Api.Models;

namespace Focusely.Api.Dtos;

public record StartSessionDto(Guid Id, SessionMode Mode, int? TargetSeconds, Guid? SubjectId);

public record SessionDto(
    Guid Id, string Mode, DateTime StartedAtUtc, DateTime? PausedAtUtc,
    int PausedSeconds, DateTime? EndedAtUtc, int? TargetSeconds,
    int StudySeconds, bool IsValidated, DateTime ServerNowUtc, Guid? SubjectId);
