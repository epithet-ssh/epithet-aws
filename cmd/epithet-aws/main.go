package main

import (
	"log/slog"
	"os"
	"strings"

	"github.com/alecthomas/kong"
	"github.com/lmittmann/tint"
)

var cli struct {
	Verbose int             `short:"v" type:"counter" help:"Increase verbosity (-v for debug, -vv for trace)"`
	CA      AwsCALambdaCLI     `cmd:"ca" help:"Run CA server as AWS Lambda function"`
	Policy  AwsPolicyLambdaCLI `cmd:"policy" help:"Run policy server as AWS Lambda function"`
}

func main() {
	if epithetCmd := os.Getenv("EPITHET_CMD"); epithetCmd != "" {
		args := strings.Fields(epithetCmd)
		os.Args = append([]string{os.Args[0]}, args...)
	}

	ktx := kong.Parse(&cli)
	logger := setupLogger()
	ktx.Bind(logger)
	err := ktx.Run()
	if err != nil {
		logger.Error("error", "error", err)
		os.Exit(1)
	}
}

func setupLogger() *slog.Logger {
	level := slog.LevelWarn
	switch cli.Verbose {
	case 0:
		level = slog.LevelWarn
	case 1:
		level = slog.LevelInfo
	default:
		level = slog.LevelDebug
	}

	logger := slog.New(tint.NewHandler(os.Stderr, &tint.Options{
		Level:      level,
		TimeFormat: "15:04:05",
	}))

	return logger
}
