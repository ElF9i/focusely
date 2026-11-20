namespace Focusely.Api.Dtos;

public record SubjectDto(Guid Id, string Name, string Color, string Emoji);
public record CreateSubjectDto(string Name, string? Color, string? Emoji);
