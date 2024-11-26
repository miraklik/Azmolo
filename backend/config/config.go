package config

import (
	"github.com/spf13/viper"
)

type Config struct {
	DBHost string `mapstructure:"DBHost"`
	DBName string `mapstructure:"DBName"`
	DBPort string `mapstructure:"DBPort"`
	DBUser string `mapstructure:"DBUser"`
	DBPass string `mapstructure:"DBPassword"`

	ServerAddress string `mapstructure:"SERVER_ADDRESS"`

	BlockChainRPC   string `mapstructure:"BLOCKCHAIN_RPC"`
	PrivateKey      string `mapstructure:"PRIVATE_KEY"`
	MarketplaceABI  string `mapstructure:"MARKETPLACE_ABI"`
	ContractAddress string `mapstructure:"CONTRACT_ADDRESS"`

	IPFSNodeAddress string `mapstructure:"IPFS_NODE_ADDRESS"`
}

func LoadConfig(path string) (Config, error) {
	var config Config

	viper.AddConfigPath(path)
	viper.SetConfigName("app")
	viper.SetConfigType("env")

	viper.AutomaticEnv()

	if err := viper.ReadInConfig(); err != nil {
		return config, err
	}

	if err := viper.Unmarshal(&config); err != nil {
		return config, err
	}

	return config, nil
}
