import React, { useState, useEffect } from "react";
import NavBar from "../components/NavBar";
import {
  Box,
  Button,
  Card,
  CardContent,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  Fab,
  TextField,
  Typography,
} from "@mui/material";
import AddIcon from "@mui/icons-material/Add";
import { addBike, getOwnerBikes } from "../utils/api";
import "../styles/HomePageOwner.css";

const HomePageOwner = () => {
  const [formData, setFormData] = useState({
    bike_name: "",
    brand: "",
    model: "",
    color: "",
    size: "",
    year: "",
    description: "",
    latitude: "45.760696",
    longitude: "21.226788",
  });
  const [bikes, setBikes] = useState([]);
  const [isDialogOpen, setIsDialogOpen] = useState(false);

  useEffect(() => {
    const fetchBikes = async () => {
      try {
        const response = await getOwnerBikes();
        setBikes(response);
      } catch (error) {
        console.error("Failed to fetch bikes:", error.message);
      }
    };

    fetchBikes();
  }, []);

  const handleDialogOpen = () => {
    setIsDialogOpen(true);
    document.activeElement.blur();
  };

  const handleDialogClose = () => {
    setIsDialogOpen(false);
    resetForm();
  };

  const resetForm = () => {
    setFormData({
      bike_name: "",
      brand: "",
      model: "",
      color: "",
      size: "",
      year: "",
      description: "",
      latitude: "45.760696",
      longitude: "21.226788",
    });
  };

  const handleInputChange = (e) => {
    const { name, value } = e.target;
    setFormData({ ...formData, [name]: value });
  };

  const handleSubmit = async (e) => {
    console.log(formData);
    e.preventDefault();
    try {
      const response = await addBike(formData);
      console.log("Bike added successfully:", response.data);
      setBikes((prevBikes) => [response.data, ...prevBikes]);
      handleDialogClose();
    } catch (error) {
      console.error("Failed to add bike:", error.message);
    }
  };

  return (
    <div className="owner-home-page">
      <NavBar userType="owner" />
      <div className="content">
        <Typography variant="h4">
          Owner Dashboard
        </Typography>
        <div className="bike-list">
          {bikes.map((bike, index) => (
            <Card key={index} className="bike-card">
              <CardContent>
                <Typography variant="h5">
                  {bike.bike_name}
                </Typography>
                <Typography variant="body2">
                  <strong>Brand:</strong> {bike.brand}
                </Typography>
                <Typography variant="body2">
                  <strong>Model:</strong> {bike.model}
                </Typography>
                <Typography variant="body2">
                  <strong>Color:</strong> {bike.color}
                </Typography>
                <Typography variant="body2">
                  <strong>Size:</strong> {bike.size}
                </Typography>
                <Typography variant="body2">
                  <strong>Year:</strong> {bike.year}
                </Typography>
                <Typography variant="body2" style={{ marginBottom: "8px" }}>
                  <strong>Description:</strong> {bike.description}
                </Typography>
                <Typography variant="body2" style={{ color: bike.is_available ? "green" : "red", fontWeight: "bold" }}>
                  <strong>Status:</strong> {bike.is_available ? "Available" : "Unavailable"}
                </Typography>
              </CardContent>
            </Card>
          ))}
        </div>

        <Fab
          color="primary"
          aria-label="add"
          className="fab"
          onClick={handleDialogOpen}
        >
          <AddIcon />
        </Fab>

        {/* Dialog Box */}
        <Dialog open={isDialogOpen} onClose={handleDialogClose}>
          <DialogTitle>Add a New Bike</DialogTitle>
          <DialogContent>
            <Box
              component="form"
              onSubmit={handleSubmit}
              sx={{
                display: "flex",
                flexDirection: "column",
                gap: 2,
                mt: 1,
              }}
            >
              <TextField
                name="bike_name"
                label="Bike Name"
                value={formData.bike_name}
                onChange={handleInputChange}
                fullWidth
                required
              />
              <TextField
                name="brand"
                label="Brand"
                value={formData.brand}
                onChange={handleInputChange}
                fullWidth
                required
              />
              <TextField
                name="model"
                label="Model"
                value={formData.model}
                onChange={handleInputChange}
                fullWidth
                required
              />
              <TextField
                name="color"
                label="Color"
                value={formData.color}
                onChange={handleInputChange}
                fullWidth
                required
              />
              <TextField
                name="size"
                label="Size"
                value={formData.size}
                onChange={handleInputChange}
                fullWidth
                required
              />
              <TextField
                name="year"
                label="Year"
                type="number"
                value={formData.year}
                onChange={handleInputChange}
                fullWidth
                required
              />
              <TextField
                name="description"
                label="Description"
                value={formData.description}
                onChange={handleInputChange}
                multiline
                rows={3}
                fullWidth
                required
              />
            </Box>
          </DialogContent>
          <DialogActions>
            <Button onClick={handleDialogClose} color="secondary">
              Cancel
            </Button>
            <Button
              onClick={handleSubmit}
              variant="contained"
              color="primary"
              type="submit"
            >
              Submit
            </Button>
          </DialogActions>
        </Dialog>
      </div>
    </div>
  );
};

export default HomePageOwner;
