using Focusely.Api.Models;

namespace Focusely.Api.Dtos;

public record ImportSessionDto(
    Guid Id, SessionMode Mode, Guid? SubjectId, int? TargetSeconds,
    DateTime StartedAtUtc, DateTime EndedAtUtc, int PausedSeconds);
