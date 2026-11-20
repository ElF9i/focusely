namespace Focusely.Api.Dtos;

public record RegisterDto(string FirstName, string LastName, string Username,
                          string Email, string Password, string? Country);
public record LoginDto(string Email, string Password);
public record AuthResponse(string Token, Guid UserId, string Username);
